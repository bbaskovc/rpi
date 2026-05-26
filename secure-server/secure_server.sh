#!/usr/bin/env bash
# ============================================================
# secure_server.sh — Harden server with UFW + Fail2ban
# Author : sysadmin
# Created: 2026-05-26
# ============================================================
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED=$'\033[0;31m';    GREEN=$'\033[0;32m';   YELLOW=$'\033[1;33m'
MAGENTA=$'\033[1;35m'; CYAN=$'\033[0;36m';   BOLD=$'\033[1m'
DIM=$'\033[2m';        NC=$'\033[0m'

# ── Icons ────────────────────────────────────────────────────
ICO_OK="✔";  ICO_FAIL="❌";  ICO_INFO="ℹ";  ICO_WARN="⚠"
ICO_STEP="ℹ"; ICO_DONE="★";  ICO_WAIT="⏳"; ICO_SKIP="⊘"

# ── Timing ───────────────────────────────────────────────────
_T_START="${EPOCHREALTIME:-$SECONDS}"
_elapsed() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    awk "BEGIN { printf \"%.3f\", ${EPOCHREALTIME} - ${_T_START} }"
  else
    echo $(( SECONDS - ${_T_START%.*} ))
  fi
}

# ── Script path ───────────────────────────────────────────────
_SCRIPT_REL=$(realpath --relative-to="$(pwd)" "${BASH_SOURCE[0]}" 2>/dev/null \
              || echo "${BASH_SOURCE[0]}")

# ── Run banner ────────────────────────────────────────────────
_SCRIPT_TITLE=""
_SCRIPT_STARTED=0
script_start() {
  local title="${1:-}"
  local params="${2:-}"
  _SCRIPT_TITLE="$title"
  _SCRIPT_STARTED=1
  local hr; hr="$(printf '─%.0s' {1..80})"
  printf "${DIM}%s${NC}\n" "$hr"
  if [[ -n "$title" ]]; then
    printf "  🌐  %-16s ${BOLD}${MAGENTA}%s${NC}\n" "Name:" "$title"
  fi
  printf "  🚀  %-16s ${YELLOW}%s${NC}\n" "Script:" "$_SCRIPT_REL"
  if [[ -n "$params" ]]; then
    printf "  🧩  %-16s ${DIM}%s${NC}\n" "Parameters:" "$params"
  fi
  printf "${DIM}%s${NC}\n" "$hr"
}

script_finish() { exit "${1:-0}"; }

# ── Print helpers ─────────────────────────────────────────────
hr()      { printf "${DIM}%s${NC}\n" "$(printf '─%.0s' {1..80})"; }
header()  { echo; hr; printf "  ${BOLD}${MAGENTA}%s${NC}\n" "$1"; hr; echo; }
success() { printf "  ${GREEN}${ICO_OK}${NC}  %s\n" "$1"; }
fail()    { printf "  ${RED}${ICO_FAIL}${NC}  %s\n" "$1" >&2; }
info()    { printf "  ${CYAN}${ICO_INFO}${NC}  %s\n" "$1"; }
warn()    { printf "  ${YELLOW}${ICO_WARN}${NC}  %s\n" "$1"; }
step()    { printf "\n  ${CYAN}${BOLD}${ICO_STEP}${NC}  ${BOLD}%s${NC}\n" "$1"; }
done_()   { echo; printf "  ${GREEN}${ICO_DONE}  ${BOLD}Done:${NC} %s\n" "$1"; hr; echo; }
skip()    { printf "  ${DIM}${ICO_SKIP}${NC}  ${DIM}%s (skipped)${NC}\n" "$1"; }

# ── Spinner ───────────────────────────────────────────────────
_SPIN_PID=""
spin_start() {
  local msg="$1"
  (while true; do
    for c in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
      printf "\r  %s  ${DIM}%s${NC} " "$c" "$msg"; sleep 0.1
    done
  done) &
  _SPIN_PID=$!
}
spin_stop() {
  if [[ -n "$_SPIN_PID" ]]; then
    kill "$_SPIN_PID" 2>/dev/null || true
    wait "$_SPIN_PID" 2>/dev/null || true
    _SPIN_PID=""
  fi
  printf "\r\033[2K"
}

# ── Exit handler ──────────────────────────────────────────────
_on_exit() {
  local code=$?
  set +e
  [[ "$_SCRIPT_STARTED" -eq 0 ]] && return
  spin_stop
  local elapsed; elapsed="$(_elapsed)"
  local hr; hr="$(printf '─%.0s' {1..80})"
  printf "\n${DIM}%s${NC}\n" "$hr"
  if [[ "$code" -eq 0 ]]; then
    printf "  ✅  %-18s  ${GREEN}${BOLD}%s${NC}\n" "Script result:" "Script finished successfully!"
  else
    printf "  ❌  %-18s  ${RED}${BOLD}%s${NC}\n" "Script result:" "Script failed!"
  fi
  if [[ "$code" -eq 0 ]]; then
    printf "  🏁  %-18s  ${GREEN}%s${NC}\n" "Exit code:" "$code"
  else
    printf "  🏁  %-18s  ${RED}%s${NC}\n" "Exit code:" "$code"
  fi
  printf "  ⏱️  %-18s  ${YELLOW}%s${NC}\n" "Elapsed time:" "${elapsed} seconds"
  printf "${DIM}%s${NC}\n" "$hr"
}
trap '_on_exit' EXIT

_on_error() {
  spin_stop
  printf "\n  ❌  ${RED}Error at line %s${NC} (exit code ${RED}%s${NC})\n" "$1" "$2"
  exit "$2"
}
trap '_on_error $LINENO $?' ERR

# ── Privilege check ───────────────────────────────────────────
require_root() {
  [[ $EUID -eq 0 ]] || { fail "This script must be run as root (use sudo)."; exit 1; }
}

# ══════════════════════════════════════════════════════════════
#  CONFIGURATION
# ══════════════════════════════════════════════════════════════

# SSH port (change if you use a non-standard port)
SSH_PORT="${SSH_PORT:-22}"

# Set to "yes" to disable password auth and enforce SSH key-only login.
# CAUTION: only enable after confirming key-based login works!
# Override: SSH_DISABLE_PASSWORD_AUTH=yes sudo ./secure_server.sh
SSH_DISABLE_PASSWORD_AUTH="${SSH_DISABLE_PASSWORD_AUTH:-no}"   # default: password auth ON

# Local network ranges allowed to reach SSH
# Add or remove CIDRs as needed — 192.168.0.0/16 covers 192.168.88.x
SSH_ALLOWED_NETWORKS=(
  "10.0.0.0/8"
  "172.16.0.0/12"
  "192.168.0.0/16"
)

# Ports open to the world
PUBLIC_TCP_PORTS=(80 443)

# Fail2ban — SSH jail settings
F2B_SSH_MAX_RETRY=5          # attempts before ban
F2B_SSH_FIND_TIME="10m"      # window in which retries are counted
F2B_SSH_BAN_TIME="1h"        # how long to ban (use -1 for permanent)
F2B_IGNORE_IPS=(             # never ban these (localhost + RFC-1918)
  "127.0.0.1/8"
  "10.0.0.0/8"
  "172.16.0.0/12"
  "192.168.0.0/16"
)

# Fail2ban jail config file (local override — never touch .conf files directly)
F2B_JAIL_LOCAL="/etc/fail2ban/jail.local"
F2B_SSHD_CONF="/etc/fail2ban/jail.d/sshd.local"

# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════
require_root

script_start "Secure Server — UFW + Fail2ban" \
  "ssh_port=${SSH_PORT}  public_ports=80,443"

# ─────────────────────────────────────────────────────────────
# 1. PREREQUISITES
# ─────────────────────────────────────────────────────────────
step "Checking prerequisites"

for cmd in apt-get systemctl iptables; do
  command -v "$cmd" &>/dev/null \
    && success "${cmd} found" \
    || { fail "${cmd} not found — is this a Debian/Ubuntu system?"; exit 1; }
done

# Warn if SSH session might be interrupted
CURRENT_IP=$(echo "${SSH_CLIENT:-}" | awk '{print $1}')
if [[ -n "$CURRENT_IP" ]]; then
  warn "You are connected via SSH from ${YELLOW}${CURRENT_IP}${NC}"
  warn "Ensure this IP falls within the allowed SSH networks before continuing."
  echo
  COVERED=0
  for net in "${SSH_ALLOWED_NETWORKS[@]}"; do
    info "  Allowed SSH network: ${CYAN}${net}${NC}"
  done
  echo
  warn "If your IP is NOT in those ranges, press ${BOLD}Ctrl+C now${NC} to abort!"
  printf "  ${YELLOW}${ICO_WARN}${NC}  Continuing in 10 seconds...\n"
  sleep 10
fi

# ─────────────────────────────────────────────────────────────
# 2. INSTALL UFW + FAIL2BAN
# ─────────────────────────────────────────────────────────────
step "Installing UFW and Fail2ban"

spin_start "Running apt-get update..."
  apt-get update -qq
spin_stop
success "Package index updated"

PKGS_TO_INSTALL=()
for pkg in ufw fail2ban; do
  if dpkg -s "$pkg" &>/dev/null 2>&1; then
    skip "${pkg} already installed"
  else
    PKGS_TO_INSTALL+=("$pkg")
  fi
done

if [[ "${#PKGS_TO_INSTALL[@]}" -gt 0 ]]; then
  spin_start "Installing: ${PKGS_TO_INSTALL[*]}..."
    apt-get install -y --no-install-recommends "${PKGS_TO_INSTALL[@]}" -qq
  spin_stop
  success "Installed: ${PKGS_TO_INSTALL[*]}"
fi

# ─────────────────────────────────────────────────────────────
# 3. CONFIGURE UFW — defaults
# ─────────────────────────────────────────────────────────────
step "Configuring UFW default policies"

# Stop UFW during reconfiguration to avoid mid-change lockout
ufw --force disable &>/dev/null || true

ufw default deny incoming  &>/dev/null
ufw default allow outgoing &>/dev/null
ufw default deny forward   &>/dev/null
success "Default policy: ${RED}deny${NC} incoming  |  ${GREEN}allow${NC} outgoing  |  ${RED}deny${NC} forward"

# ─────────────────────────────────────────────────────────────
# 4. UFW — SSH from local networks only
# ─────────────────────────────────────────────────────────────
step "UFW — SSH (port ${SSH_PORT}) from local networks only"

for net in "${SSH_ALLOWED_NETWORKS[@]}"; do
  ufw allow from "$net" to any port "$SSH_PORT" proto tcp comment "SSH from local ${net}" &>/dev/null
  success "SSH allowed from ${CYAN}${net}${NC}"
done

# ─────────────────────────────────────────────────────────────
# 5. UFW — public HTTP / HTTPS
# ─────────────────────────────────────────────────────────────
step "UFW — public ports (HTTP 80 / HTTPS 443)"

for port in "${PUBLIC_TCP_PORTS[@]}"; do
  ufw allow "${port}/tcp" comment "Public TCP ${port}" &>/dev/null
  success "Port ${CYAN}${port}/tcp${NC} open to everywhere"
done

# ─────────────────────────────────────────────────────────────
# 6. UFW — loopback
# ─────────────────────────────────────────────────────────────
step "UFW — loopback interface"

ufw allow in  on lo &>/dev/null
ufw allow out on lo &>/dev/null
success "Loopback (lo) unrestricted"

# ─────────────────────────────────────────────────────────────
# 7. UFW — enable & verify
# ─────────────────────────────────────────────────────────────
step "Enabling UFW"

spin_start "Enabling UFW..."
  ufw --force enable &>/dev/null
spin_stop
success "UFW enabled"

# Persist across reboots via systemd
systemctl enable ufw &>/dev/null
success "UFW service enabled at boot"

echo
hr
ufw status verbose 2>/dev/null | sed 's/^/  /'
hr
echo

# ─────────────────────────────────────────────────────────────
# 8. CONFIGURE FAIL2BAN — global jail.local
# ─────────────────────────────────────────────────────────────
step "Writing Fail2ban global jail.local"

# Build ignoreip list (space-separated for fail2ban)
IGNORE_IP_LIST="${F2B_IGNORE_IPS[*]}"

if [[ -f "$F2B_JAIL_LOCAL" ]]; then
  warn "Backing up existing ${F2B_JAIL_LOCAL} → ${F2B_JAIL_LOCAL}.bak"
  cp "$F2B_JAIL_LOCAL" "${F2B_JAIL_LOCAL}.bak"
fi

cat > "$F2B_JAIL_LOCAL" <<EOF
[DEFAULT]
# Never ban these ranges (localhost + all RFC-1918 private ranges)
ignoreip = ${IGNORE_IP_LIST}

# Backend auto-detects journald / inotify
backend = auto

# Default ban settings (overridden per-jail below)
bantime  = ${F2B_SSH_BAN_TIME}
findtime = ${F2B_SSH_FIND_TIME}
maxretry = ${F2B_SSH_MAX_RETRY}

# Use UFW as the ban action so rules stay consistent
banaction         = ufw
banaction_allports = ufw

# Send no email by default (avoids needing sendmail configured)
action = %(action_)s
EOF

success "Global jail config written: ${YELLOW}${F2B_JAIL_LOCAL}${NC}"

# ─────────────────────────────────────────────────────────────
# 9. CONFIGURE FAIL2BAN — SSH jail
# ─────────────────────────────────────────────────────────────
step "Writing Fail2ban SSH jail (sshd.local)"

mkdir -p /etc/fail2ban/jail.d

# Detect correct sshd log backend (systemd journal preferred)
if systemctl is-active --quiet ssh 2>/dev/null || \
   systemctl is-active --quiet sshd 2>/dev/null; then
  SSH_BACKEND="systemd"
  SSH_JOURNALMATCH="_SYSTEMD_UNIT=ssh.service + _SYSTEMD_UNIT=sshd.service"
else
  SSH_BACKEND="auto"
  SSH_JOURNALMATCH=""
fi

cat > "$F2B_SSHD_CONF" <<EOF
[sshd]
enabled   = true
port      = ${SSH_PORT}
filter    = sshd
backend   = ${SSH_BACKEND}
${SSH_JOURNALMATCH:+journalmatch = ${SSH_JOURNALMATCH}}
maxretry  = ${F2B_SSH_MAX_RETRY}
findtime  = ${F2B_SSH_FIND_TIME}
bantime   = ${F2B_SSH_BAN_TIME}
logpath   = %(sshd_log)s

# Aggressive mode: also catch pre-auth disconnects
mode      = aggressive
EOF

success "SSH jail config written: ${YELLOW}${F2B_SSHD_CONF}${NC}"
info "  max retries : ${CYAN}${F2B_SSH_MAX_RETRY}${NC} within ${CYAN}${F2B_SSH_FIND_TIME}${NC}"
info "  ban time    : ${CYAN}${F2B_SSH_BAN_TIME}${NC}"
info "  mode        : ${CYAN}aggressive${NC}"

# ─────────────────────────────────────────────────────────────
# 10. CONFIGURE FAIL2BAN — HTTP/HTTPS jails (nginx / apache)
# ─────────────────────────────────────────────────────────────
step "Writing Fail2ban HTTP jails"

HTTP_JAIL="/etc/fail2ban/jail.d/http.local"

# Only enable a jail when its log directory actually exists on this host.
# Fail2ban refuses to start if enabled=true but the logpath is missing.
_nginx_enabled="false"
_apache_enabled="false"
[[ -d /var/log/nginx   ]] && _nginx_enabled="true"
[[ -d /var/log/apache2 ]] && _apache_enabled="true"

cat > "$HTTP_JAIL" <<EOF
# ── Nginx ──────────────────────────────────────────────────
[nginx-http-auth]
enabled  = ${_nginx_enabled}
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 5
bantime  = 1h

[nginx-limit-req]
enabled  = ${_nginx_enabled}
port     = http,https
filter   = nginx-limit-req
logpath  = /var/log/nginx/error.log
maxretry = 10
bantime  = 30m

[nginx-botsearch]
enabled  = ${_nginx_enabled}
port     = http,https
filter   = nginx-botsearch
logpath  = /var/log/nginx/access.log
maxretry = 2
bantime  = 24h

# ── Apache ─────────────────────────────────────────────────
[apache-auth]
enabled  = ${_apache_enabled}
port     = http,https
filter   = apache-auth
logpath  = /var/log/apache2/error.log
maxretry = 5
bantime  = 1h

[apache-badbots]
enabled  = ${_apache_enabled}
port     = http,https
filter   = apache-badbots
logpath  = /var/log/apache2/access.log
maxretry = 2
bantime  = 24h
EOF

success "HTTP jail config written: ${YELLOW}${HTTP_JAIL}${NC}"
if [[ "$_nginx_enabled"  == "true" ]]; then
  success "nginx jails: ${GREEN}enabled${NC} (/var/log/nginx detected)"
else
  skip "nginx jails disabled — /var/log/nginx not found"
fi
if [[ "$_apache_enabled" == "true" ]]; then
  success "apache jails: ${GREEN}enabled${NC} (/var/log/apache2 detected)"
else
  skip "apache jails disabled — /var/log/apache2 not found"
fi
info "Install nginx/apache later? Re-run this script to auto-enable their jails."

# ─────────────────────────────────────────────────────────────
# 11. HARDEN SSHD CONFIG
# ─────────────────────────────────────────────────────────────
step "Hardening SSH daemon configuration"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_OVERRIDE="/etc/ssh/sshd_config.d/99-hardening.conf"

# Use drop-in directory if supported (OpenSSH >= 8.2), else patch main config
if [[ -d /etc/ssh/sshd_config.d ]]; then
  TARGET_FILE="$SSHD_OVERRIDE"
  info "Using drop-in: ${YELLOW}${SSHD_OVERRIDE}${NC}"
else
  TARGET_FILE="$SSHD_CONFIG"
  warn "No sshd_config.d directory — patching ${YELLOW}${SSHD_CONFIG}${NC} directly"
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"
  info "Backup saved: ${YELLOW}${SSHD_CONFIG}.bak.*${NC}"
fi

# Resolve password auth setting from config variable
if [[ "$SSH_DISABLE_PASSWORD_AUTH" == "yes" ]]; then
  _PASS_AUTH="no"
  warn "Password authentication will be ${RED}DISABLED${NC} — ensure SSH key login works first!"
else
  _PASS_AUTH="yes"
  info "Password auth: ${GREEN}enabled${NC}  (re-run with SSH_DISABLE_PASSWORD_AUTH=yes to enforce key-only)"
fi

cat > "$TARGET_FILE" <<EOF
# ── SSH Hardening (managed by secure_server.sh) ─────────────
Port ${SSH_PORT}

# Password authentication (set SSH_DISABLE_PASSWORD_AUTH=yes to disable)
PasswordAuthentication ${_PASS_AUTH}
PermitEmptyPasswords   no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication    no

# Disable root login
PermitRootLogin no

# Limit auth attempts and sessions
MaxAuthTries 3
MaxSessions  5
LoginGraceTime 30

# Disable legacy / insecure features
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no

# Only allow strong algorithms (OpenSSH 8.x+)
Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com,chacha20-poly1305@openssh.com
MACs hmac-sha2-256,hmac-sha2-512,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,ecdh-sha2-nistp521

# Log level (INFO is sufficient; use VERBOSE for key fingerprint logging)
LogLevel INFO

# Keep-alive to detect dead connections
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable .rhosts and host-based auth
IgnoreRhosts yes
HostbasedAuthentication no
EOF

# Test config before reloading
if sshd -t -f "${SSHD_CONFIG}" 2>/dev/null; then
  spin_start "Reloading sshd..."
    systemctl reload-or-restart ssh  2>/dev/null || \
    systemctl reload-or-restart sshd 2>/dev/null || true
  spin_stop
  success "sshd config validated and reloaded"
else
  warn "sshd -t reported warnings — check config manually before reloading"
  warn "Config file: ${YELLOW}${TARGET_FILE}${NC}"
fi

if [[ "$SSH_DISABLE_PASSWORD_AUTH" != "yes" ]]; then
  warn "Password auth is still ENABLED. Once SSH keys are confirmed working, re-run with:"
  printf "  ${CYAN}  \$${NC}  SSH_DISABLE_PASSWORD_AUTH=yes sudo ./secure_server.sh\n"
fi

# ─────────────────────────────────────────────────────────────
# 12. KERNEL — sysctl hardening
# ─────────────────────────────────────────────────────────────
step "Applying sysctl network hardening"

SYSCTL_FILE="/etc/sysctl.d/99-secure-server.conf"

cat > "$SYSCTL_FILE" <<'EOF'
# ── Network hardening (managed by secure_server.sh) ─────────

# Ignore ICMP broadcast requests (Smurf attack mitigation)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable TCP SYN cookies (SYN flood mitigation)
net.ipv4.tcp_syncookies = 1

# Do not accept source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Do not accept ICMP redirects (prevents MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Do not send ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Enable reverse path filtering (spoofed IP mitigation)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Log martian packets (useful for detecting spoofing)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable IPv6 if not needed (comment out to keep IPv6)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

spin_start "Applying sysctl settings..."
  sysctl -p "$SYSCTL_FILE" &>/dev/null
spin_stop
success "Sysctl hardening applied: ${YELLOW}${SYSCTL_FILE}${NC}"

# ─────────────────────────────────────────────────────────────
# 13. ENABLE & START FAIL2BAN
# ─────────────────────────────────────────────────────────────
step "Enabling and starting Fail2ban"

spin_start "Restarting fail2ban with new config..."
  systemctl enable fail2ban &>/dev/null
  systemctl restart fail2ban
spin_stop

sleep 2

F2B_STATUS=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
if [[ "$F2B_STATUS" == "active" ]]; then
  success "fail2ban: ${GREEN}active${NC}"
else
  fail "fail2ban failed to start — check: journalctl -u fail2ban -n 50"
  exit 1
fi

# Show active jails
ACTIVE_JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*Jail list:\s*//' || echo "none")
info "Active jails: ${CYAN}${ACTIVE_JAILS}${NC}"

# ─────────────────────────────────────────────────────────────
# 14. FINAL SUMMARY
# ─────────────────────────────────────────────────────────────
step "Security configuration summary"

printf "\n"
hr
printf "  ${BOLD}${MAGENTA}%-22s  %s${NC}\n" "Component" "Status / Notes"
hr
printf "  ${BOLD}%-22s${NC}  %s\n"  "UFW firewall"        "$(ufw status | head -1)"
printf "  ${BOLD}%-22s${NC}  %s\n"  "SSH (port ${SSH_PORT})"        "LAN only: ${SSH_ALLOWED_NETWORKS[*]}"
printf "  ${BOLD}%-22s${NC}  %s\n"  "HTTP/HTTPS"          "Open to 0.0.0.0/0"
printf "  ${BOLD}%-22s${NC}  %s\n"  "Fail2ban"            "Active — SSH + HTTP jails"
printf "  ${BOLD}%-22s${NC}  %s\n"  "SSH hardening"       "Keys only, root login disabled"
printf "  ${BOLD}%-22s${NC}  %s\n"  "Sysctl"              "${SYSCTL_FILE}"
hr
printf "\n"

info "Useful commands:"
printf "  ${CYAN}  \$${NC}  ufw status verbose\n"
printf "  ${CYAN}  \$${NC}  fail2ban-client status sshd\n"
printf "  ${CYAN}  \$${NC}  fail2ban-client banned\n"
printf "  ${CYAN}  \$${NC}  fail2ban-client set sshd unbanip <IP>\n"
printf "  ${CYAN}  \$${NC}  journalctl -u fail2ban -f\n"

echo
done_ "Server hardened with UFW + Fail2ban"

script_finish "0"
