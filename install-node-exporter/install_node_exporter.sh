#!/usr/bin/env bash
# ============================================================
# install_node_exporter.sh — Install Prometheus Node Exporter
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

# Leave empty to auto-resolve latest release from GitHub
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-}"

# System user / group that runs the service (no login shell, no home)
NE_USER="node_exporter"
NE_GROUP="node_exporter"

# Where the binary lives
NE_BIN="/usr/local/bin/node_exporter"

# Systemd service name
NE_SERVICE="node_exporter"

# Metrics port
NE_PORT="9100"

# Collectors to enable on top of defaults (space-separated)
# See: https://github.com/prometheus/node_exporter#enabled-by-default
EXTRA_COLLECTORS="systemd"   # useful for service health in Grafana

# Temp dir for download
WORK_DIR="$(mktemp -d)"

# ══════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════

_arch_ne() {
  local machine; machine="$(uname -m)"
  case "$machine" in
    x86_64)          echo "amd64"   ;;
    aarch64|arm64)   echo "arm64"   ;;
    armv7l|armv6l)   echo "armv7"   ;;
    i386|i686)       echo "386"     ;;
    *)
      fail "Unsupported architecture: ${machine}"
      exit 1
      ;;
  esac
}

_cleanup() { rm -rf "$WORK_DIR"; }
trap '_cleanup' EXIT

# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════
require_root

ARCH="$(_arch_ne)"

script_start "Install Prometheus Node Exporter" \
  "arch=${ARCH}  port=${NE_PORT}  user=${NE_USER}"

# ─────────────────────────────────────────────────────────────
# 1. CHECK IF ALREADY INSTALLED
# ─────────────────────────────────────────────────────────────
step "Checking current installation"

if [[ -x "$NE_BIN" ]]; then
  CURRENT_VER=$("$NE_BIN" --version 2>&1 | grep -oP 'version \K[^\s]+' | head -1 || echo "unknown")
  warn "node_exporter already installed: ${YELLOW}${CURRENT_VER}${NC} at ${YELLOW}${NE_BIN}${NC}"
  info "Script will reinstall / upgrade to latest stable."
else
  info "No existing installation found — fresh install"
fi

# ─────────────────────────────────────────────────────────────
# 2. RESOLVE LATEST VERSION
# ─────────────────────────────────────────────────────────────
step "Resolving Node Exporter version"

if [[ -z "$NODE_EXPORTER_VERSION" ]]; then
  spin_start "Fetching latest release tag from GitHub..."
    NODE_EXPORTER_VERSION=$(curl -fsSL \
      "https://api.github.com/repos/prometheus/node_exporter/releases/latest" \
      | grep -oP '"tag_name":\s*"\Kv[^"]+')
  spin_stop
fi

# Strip leading 'v' for the tarball filename
NE_VERSION_CLEAN="${NODE_EXPORTER_VERSION#v}"
success "Target version: ${GREEN}${NODE_EXPORTER_VERSION}${NC}"

# ─────────────────────────────────────────────────────────────
# 3. DOWNLOAD & VERIFY
# ─────────────────────────────────────────────────────────────
step "Downloading Node Exporter ${NODE_EXPORTER_VERSION}"

BASE_URL="https://github.com/prometheus/node_exporter/releases/download/${NODE_EXPORTER_VERSION}"
TARBALL="node_exporter-${NE_VERSION_CLEAN}.linux-${ARCH}.tar.gz"
SHA256_FILE="sha256sums.txt"

spin_start "Downloading ${TARBALL}..."
  curl -fsSL "${BASE_URL}/${TARBALL}"     -o "${WORK_DIR}/${TARBALL}"
  curl -fsSL "${BASE_URL}/${SHA256_FILE}" -o "${WORK_DIR}/${SHA256_FILE}"
spin_stop
success "Download complete"

spin_start "Verifying SHA256 checksum..."
  pushd "$WORK_DIR" > /dev/null
    grep "${TARBALL}" "${SHA256_FILE}" | sha256sum --check --status
  popd > /dev/null
spin_stop
success "Checksum verified"

# ─────────────────────────────────────────────────────────────
# 4. EXTRACT & INSTALL BINARY
# ─────────────────────────────────────────────────────────────
step "Installing binary to ${YELLOW}${NE_BIN}${NC}"

spin_start "Extracting tarball..."
  tar -xzf "${WORK_DIR}/${TARBALL}" -C "$WORK_DIR"
spin_stop

EXTRACTED_DIR="${WORK_DIR}/node_exporter-${NE_VERSION_CLEAN}.linux-${ARCH}"
install -m 0755 "${EXTRACTED_DIR}/node_exporter" "$NE_BIN"
success "Binary installed: ${YELLOW}${NE_BIN}${NC}"

# ─────────────────────────────────────────────────────────────
# 5. CREATE SYSTEM USER
# ─────────────────────────────────────────────────────────────
step "Creating system user & group"

if getent group "$NE_GROUP" &>/dev/null; then
  skip "Group '${NE_GROUP}' already exists"
else
  groupadd --system "$NE_GROUP"
  success "Group created: ${NE_GROUP}"
fi

if id "$NE_USER" &>/dev/null; then
  skip "User '${NE_USER}' already exists"
else
  useradd \
    --system \
    --no-create-home \
    --shell /usr/sbin/nologin \
    --gid "$NE_GROUP" \
    "$NE_USER"
  success "System user created: ${NE_USER} (no login shell, no home)"
fi

# Lock down the binary ownership
chown root:root "$NE_BIN"

# ─────────────────────────────────────────────────────────────
# 6. BUILD COLLECTOR FLAGS
# ─────────────────────────────────────────────────────────────
step "Configuring collectors"

COLLECTOR_FLAGS=""
for collector in $EXTRA_COLLECTORS; do
  COLLECTOR_FLAGS="${COLLECTOR_FLAGS} --collector.${collector}"
  info "Extra collector enabled: ${CYAN}${collector}${NC}"
done

[[ -z "$COLLECTOR_FLAGS" ]] && skip "No extra collectors configured (defaults only)"

# ─────────────────────────────────────────────────────────────
# 7. CREATE SYSTEMD SERVICE
# ─────────────────────────────────────────────────────────────
step "Creating systemd service unit"

SERVICE_FILE="/etc/systemd/system/${NE_SERVICE}.service"

if [[ -f "$SERVICE_FILE" ]]; then
  warn "Service file already exists — overwriting with updated config"
  systemctl stop "$NE_SERVICE" 2>/dev/null || true
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${NE_USER}
Group=${NE_GROUP}
ExecStart=${NE_BIN} \\
    --web.listen-address=0.0.0.0:${NE_PORT} \\
    --web.telemetry-path=/metrics \\
    --collector.disable-defaults=false${COLLECTOR_FLAGS:+ \\
    }${COLLECTOR_FLAGS}

# Hardening
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
CapabilityBoundingSet=
AmbientCapabilities=
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

success "Service unit written: ${YELLOW}${SERVICE_FILE}${NC}"

# ─────────────────────────────────────────────────────────────
# 8. RELOAD SYSTEMD & START SERVICE
# ─────────────────────────────────────────────────────────────
step "Enabling and starting ${NE_SERVICE} service"

spin_start "Reloading systemd daemon..."
  systemctl daemon-reload
spin_stop
success "systemd daemon reloaded"

spin_start "Enabling and starting ${NE_SERVICE}..."
  systemctl enable --now "$NE_SERVICE"
spin_stop

# Give it a moment to bind the port
sleep 2

STATUS=$(systemctl is-active "$NE_SERVICE" 2>/dev/null || echo "inactive")
if [[ "$STATUS" == "active" ]]; then
  success "Service ${NE_SERVICE}: ${GREEN}active${NC}"
else
  fail "Service ${NE_SERVICE} is ${STATUS} — check: journalctl -u ${NE_SERVICE} -n 50"
  exit 1
fi

# ─────────────────────────────────────────────────────────────
# 9. FIREWALL — open port 9100
# ─────────────────────────────────────────────────────────────
step "Configuring firewall for port ${NE_PORT}/tcp"

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  if ufw status | grep -q "${NE_PORT}"; then
    skip "ufw rule for port ${NE_PORT} already exists"
  else
    ufw allow "${NE_PORT}/tcp" comment "Prometheus Node Exporter" > /dev/null
    success "ufw: allowed port ${NE_PORT}/tcp"
  fi
elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
  if firewall-cmd --query-port="${NE_PORT}/tcp" --permanent &>/dev/null; then
    skip "firewalld rule for port ${NE_PORT} already exists"
  else
    firewall-cmd --permanent --add-port="${NE_PORT}/tcp" > /dev/null
    firewall-cmd --reload > /dev/null
    success "firewalld: allowed port ${NE_PORT}/tcp (permanent)"
  fi
else
  skip "No active firewall detected (ufw/firewalld) — skipping"
  warn "If you use iptables manually, allow TCP port ${NE_PORT} from your Prometheus server"
fi

# ─────────────────────────────────────────────────────────────
# 10. SMOKE TEST — metrics endpoint
# ─────────────────────────────────────────────────────────────
step "Smoke test — querying metrics endpoint"

METRICS_URL="http://127.0.0.1:${NE_PORT}/metrics"

spin_start "Waiting for metrics on ${METRICS_URL}..."
  MAX_RETRIES=10
  RETRY=0
  HTTP_OK=0
  while [[ "$RETRY" -lt "$MAX_RETRIES" ]]; do
    if curl -fsSL --max-time 3 "$METRICS_URL" | grep -q "node_exporter_build_info"; then
      HTTP_OK=1
      break
    fi
    RETRY=$(( RETRY + 1 ))
    sleep 1
  done
spin_stop

if [[ "$HTTP_OK" -eq 1 ]]; then
  success "Metrics endpoint is responding at ${GREEN}${METRICS_URL}${NC}"
  METRIC_COUNT=$(curl -fsSL "$METRICS_URL" 2>/dev/null | grep -c "^# HELP" || echo "?")
  info "Exposed metrics: ${CYAN}${METRIC_COUNT}${NC}"
else
  warn "Metrics endpoint not yet reachable — service may still be starting"
  info "Check manually: ${CYAN}curl http://127.0.0.1:${NE_PORT}/metrics | head -20${NC}"
fi

# ─────────────────────────────────────────────────────────────
# 11. PROMETHEUS CONFIG SNIPPET
# ─────────────────────────────────────────────────────────────
step "Prometheus scrape config snippet"

HOST_IP=$(hostname -I | awk '{print $1}')

printf "\n"
hr
printf "  ${BOLD}${CYAN}Add this job to your prometheus.yml scrape_configs:${NC}\n\n"
printf "  ${DIM}scrape_configs:${NC}\n"
printf "  ${DIM}  - job_name: ${GREEN}'node'${NC}\n"
printf "  ${DIM}    static_configs:${NC}\n"
printf "  ${DIM}      - targets: [${GREEN}'%s:%s'${NC}${DIM}]${NC}\n" "$HOST_IP" "$NE_PORT"
printf "  ${DIM}    scrape_interval: 15s${NC}\n"
printf "  ${DIM}    scrape_timeout:  10s${NC}\n"
hr
printf "\n"

info "Grafana dashboard recommendation:"
info "  Import dashboard ID ${BOLD}${CYAN}1860${NC} (Node Exporter Full) from grafana.com"
info "  Metrics URL: ${YELLOW}http://${HOST_IP}:${NE_PORT}/metrics${NC}"

# ─────────────────────────────────────────────────────────────
# 12. VERSION CONFIRMATION
# ─────────────────────────────────────────────────────────────
step "Installed version"

NE_VER_INSTALLED=$("$NE_BIN" --version 2>&1 | head -1 || echo "unknown")
success "${NE_VER_INSTALLED}"

echo
done_ "Node Exporter installed and running on port ${NE_PORT}"

script_finish "0"
