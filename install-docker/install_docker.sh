#!/usr/bin/env bash
# ============================================================
# install_docker.sh — Install Docker Engine + Compose & prep user
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
  [[ -n "$_SCRIPT_TITLE" ]] && \
    printf "   ${MAGENTA}◆${NC}  %-18s  ${BOLD}%s${NC}\n" "Script name:" "$_SCRIPT_TITLE"
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

# The non-root user to add to the docker group.
# Override via:  DOCKER_USER=myuser sudo ./install_docker.sh
DOCKER_USER="${DOCKER_USER:-${SUDO_USER:-}}"

# Docker Compose plugin version to pin (leave empty = latest)
COMPOSE_VERSION="${COMPOSE_VERSION:-}"

# Optional: custom Docker daemon settings written to /etc/docker/daemon.json
DOCKER_LOG_DRIVER="json-file"
DOCKER_LOG_MAX_SIZE="20m"
DOCKER_LOG_MAX_FILE="5"

# ══════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════

# Detect distro ID and version
_distro_id()  { grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"' 2>/dev/null || echo "unknown"; }
_distro_ver() { grep -oP '(?<=^VERSION_CODENAME=).+' /etc/os-release | tr -d '"' 2>/dev/null \
                || grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"' 2>/dev/null \
                || echo "unknown"; }
_arch()       { dpkg --print-architecture 2>/dev/null || uname -m; }

# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════
require_root

script_start "Install Docker Engine + Compose" \
  "user=${DOCKER_USER:-<none>}  distro=$(_distro_id)/$(_distro_ver)  arch=$(_arch)"

# ─────────────────────────────────────────────────────────────
# 1. PREREQUISITES
# ─────────────────────────────────────────────────────────────
step "Checking prerequisites"

# Must be Debian/Ubuntu family
DISTRO_ID="$(_distro_id)"
case "$DISTRO_ID" in
  ubuntu|debian|raspbian|linuxmint|pop) ;;
  *)
    fail "Unsupported distro: ${DISTRO_ID}. This script supports Debian/Ubuntu-based systems."
    exit 1
    ;;
esac
success "Distro: ${DISTRO_ID} ($(_distro_ver))"

# Warn if no target user supplied
if [[ -z "$DOCKER_USER" ]]; then
  warn "No DOCKER_USER set — Docker will be installed but no user will be added to the docker group."
  warn "Re-run with:  DOCKER_USER=yourname sudo ./install_docker.sh"
else
  if id "$DOCKER_USER" &>/dev/null; then
    success "Target user: ${YELLOW}${DOCKER_USER}${NC}"
  else
    fail "User '${DOCKER_USER}' does not exist on this system."
    exit 1
  fi
fi

for cmd in curl gpg apt-get systemctl; do
  if command -v "$cmd" &>/dev/null; then
    success "${cmd} found"
  else
    fail "${cmd} is required but not installed."
    exit 1
  fi
done

# ─────────────────────────────────────────────────────────────
# 2. REMOVE OLD / CONFLICTING PACKAGES
# ─────────────────────────────────────────────────────────────
step "Removing conflicting legacy Docker packages"

LEGACY_PKGS=(
  docker
  docker-engine
  docker.io
  containerd
  runc
  docker-compose          # v1 standalone
  docker-doc
  podman-docker
)

REMOVED=0
for pkg in "${LEGACY_PKGS[@]}"; do
  if dpkg -s "$pkg" &>/dev/null 2>&1; then
    spin_start "Removing ${pkg}..."
      apt-get remove -y "$pkg" -qq 2>/dev/null || true
    spin_stop
    success "Removed legacy package: ${pkg}"
    REMOVED=$(( REMOVED + 1 ))
  fi
done

if [[ "$REMOVED" -eq 0 ]]; then
  skip "No legacy Docker packages found"
fi

# ─────────────────────────────────────────────────────────────
# 3. INSTALL DEPENDENCIES
# ─────────────────────────────────────────────────────────────
step "Installing required dependencies"

spin_start "Running apt-get update..."
  apt-get update -qq
spin_stop

spin_start "Installing ca-certificates, curl, gnupg, lsb-release..."
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    -qq
spin_stop
success "Dependencies installed"

# ─────────────────────────────────────────────────────────────
# 4. ADD DOCKER OFFICIAL GPG KEY
# ─────────────────────────────────────────────────────────────
step "Adding Docker official GPG key"

KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="${KEYRING_DIR}/docker.gpg"

install -m 0755 -d "$KEYRING_DIR"

if [[ -f "$KEYRING_FILE" ]]; then
  skip "Docker GPG key already present at ${KEYRING_FILE}"
else
  spin_start "Downloading Docker GPG key..."
    curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" \
      | gpg --dearmor -o "$KEYRING_FILE"
    chmod a+r "$KEYRING_FILE"
  spin_stop
  success "GPG key saved to ${YELLOW}${KEYRING_FILE}${NC}"
fi

# ─────────────────────────────────────────────────────────────
# 5. ADD DOCKER APT REPOSITORY
# ─────────────────────────────────────────────────────────────
step "Adding Docker APT repository"

REPO_FILE="/etc/apt/sources.list.d/docker.list"
ARCH="$(_arch)"
CODENAME="$(lsb_release -cs)"

# Raspbian maps to debian repo
REPO_DISTRO="$DISTRO_ID"
[[ "$DISTRO_ID" == "raspbian" ]] && REPO_DISTRO="debian"

REPO_LINE="deb [arch=${ARCH} signed-by=${KEYRING_FILE}] https://download.docker.com/linux/${REPO_DISTRO} ${CODENAME} stable"

if [[ -f "$REPO_FILE" ]] && grep -qF "download.docker.com" "$REPO_FILE" 2>/dev/null; then
  skip "Docker repository already configured"
else
  echo "$REPO_LINE" > "$REPO_FILE"
  success "Repository added: ${YELLOW}${REPO_FILE}${NC}"
fi

spin_start "Updating package index with Docker repository..."
  apt-get update -qq
spin_stop
success "Package index updated"

# ─────────────────────────────────────────────────────────────
# 6. INSTALL DOCKER ENGINE
# ─────────────────────────────────────────────────────────────
step "Installing Docker Engine"

DOCKER_PKGS=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
)

# Check if already installed
if dpkg -s docker-ce &>/dev/null 2>&1; then
  CURRENT_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
  skip "Docker CE already installed (version ${CURRENT_VER})"
else
  spin_start "Installing docker-ce, docker-ce-cli, containerd.io, buildx, compose plugin..."
    apt-get install -y --no-install-recommends "${DOCKER_PKGS[@]}" -qq
  spin_stop
  success "Docker Engine installed"
fi

# ─────────────────────────────────────────────────────────────
# 7. CONFIGURE DOCKER DAEMON
# ─────────────────────────────────────────────────────────────
step "Configuring Docker daemon"

DAEMON_JSON="/etc/docker/daemon.json"
mkdir -p /etc/docker

if [[ -f "$DAEMON_JSON" ]]; then
  skip "daemon.json already exists — not overwriting ${YELLOW}${DAEMON_JSON}${NC}"
else
  cat > "$DAEMON_JSON" <<EOF
{
  "log-driver": "${DOCKER_LOG_DRIVER}",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILE}"
  },
  "storage-driver": "overlay2"
}
EOF
  success "Daemon config written to ${YELLOW}${DAEMON_JSON}${NC}"
  info "  log-driver : ${DOCKER_LOG_DRIVER}"
  info "  max-size   : ${DOCKER_LOG_MAX_SIZE}"
  info "  max-file   : ${DOCKER_LOG_MAX_FILE}"
  info "  storage    : overlay2"
fi

# ─────────────────────────────────────────────────────────────
# 8. ENABLE & START DOCKER
# ─────────────────────────────────────────────────────────────
step "Enabling and starting Docker services"

spin_start "Enabling containerd..."
  systemctl enable --now containerd
spin_stop
success "containerd enabled and running"

spin_start "Enabling docker..."
  systemctl enable --now docker
spin_stop
success "docker enabled and running"

# Verify services are active
for svc in containerd docker; do
  STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
  if [[ "$STATUS" == "active" ]]; then
    success "Service ${svc}: ${GREEN}active${NC}"
  else
    warn "Service ${svc} status: ${YELLOW}${STATUS}${NC}"
  fi
done

# ─────────────────────────────────────────────────────────────
# 9. ADD USER TO DOCKER GROUP
# ─────────────────────────────────────────────────────────────
step "Configuring docker group permissions"

# Ensure docker group exists
if ! getent group docker &>/dev/null; then
  groupadd docker
  success "Created group: docker"
fi

if [[ -n "$DOCKER_USER" ]]; then
  if id -nG "$DOCKER_USER" | grep -qw docker; then
    skip "${DOCKER_USER} is already in the docker group"
  else
    usermod -aG docker "$DOCKER_USER"
    success "Added ${YELLOW}${DOCKER_USER}${NC} to the docker group"
    warn "User must log out and back in (or run ${CYAN}newgrp docker${NC}) for group to take effect"
  fi
else
  skip "No DOCKER_USER set — skipping group assignment"
fi

# ─────────────────────────────────────────────────────────────
# 10. INSTALL DOCKER COMPOSE STANDALONE (v2) — optional fallback
# ─────────────────────────────────────────────────────────────
step "Verifying Docker Compose (plugin)"

if docker compose version &>/dev/null 2>&1; then
  COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "unknown")
  success "Docker Compose plugin: ${GREEN}v${COMPOSE_VER}${NC}"
else
  warn "docker compose plugin not responding — attempting standalone install"
  COMPOSE_BIN="/usr/local/bin/docker-compose"
  if [[ -x "$COMPOSE_BIN" ]]; then
    skip "Standalone docker-compose already at ${COMPOSE_BIN}"
  else
    spin_start "Fetching latest docker-compose release tag..."
      if [[ -z "$COMPOSE_VERSION" ]]; then
        COMPOSE_VERSION=$(curl -fsSL \
          "https://api.github.com/repos/docker/compose/releases/latest" \
          | grep -oP '"tag_name":\s*"\K[^"]+')
      fi
    spin_stop
    info "Compose version: ${COMPOSE_VERSION}"

    COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
    spin_start "Downloading docker-compose ${COMPOSE_VERSION}..."
      curl -fsSL "$COMPOSE_URL" -o "$COMPOSE_BIN"
      chmod +x "$COMPOSE_BIN"
    spin_stop
    success "docker-compose installed at ${YELLOW}${COMPOSE_BIN}${NC}"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 11. CONFIGURE DOCKER LOGROTATE
# ─────────────────────────────────────────────────────────────
step "Setting up logrotate for Docker container logs"

LOGROTATE_FILE="/etc/logrotate.d/docker-containers"
if [[ -f "$LOGROTATE_FILE" ]]; then
  skip "Docker logrotate config already exists"
else
  cat > "$LOGROTATE_FILE" <<'EOF'
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
  success "Logrotate config written to ${YELLOW}${LOGROTATE_FILE}${NC}"
fi

# ─────────────────────────────────────────────────────────────
# 12. SMOKE TEST
# ─────────────────────────────────────────────────────────────
step "Running smoke test (docker run hello-world)"

spin_start "Pulling and running hello-world container..."
  if docker run --rm hello-world &>/dev/null; then
    spin_stop
    success "hello-world container ran successfully — Docker is fully operational"
  else
    spin_stop
    warn "hello-world test failed — Docker may need a moment to settle, or check logs with: journalctl -u docker"
  fi

# ─────────────────────────────────────────────────────────────
# 13. SUMMARY
# ─────────────────────────────────────────────────────────────
step "Installation summary"

DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "N/A")
info "Docker Engine  : ${GREEN}${DOCKER_VER}${NC}"
info "Docker socket  : ${YELLOW}/var/run/docker.sock${NC}"
info "Daemon config  : ${YELLOW}/etc/docker/daemon.json${NC}"
info "Storage driver : ${CYAN}overlay2${NC}"

if [[ -n "$DOCKER_USER" ]]; then
  echo
  warn "IMPORTANT — Next steps for user ${BOLD}${DOCKER_USER}${NC}:"
  info "  Run one of the following to activate docker group without rebooting:"
  printf "  ${CYAN}  \$${NC}  newgrp docker\n"
  printf "  ${CYAN}  \$${NC}  su - %s\n" "$DOCKER_USER"
  info "  Then verify with:"
  printf "  ${CYAN}  \$${NC}  docker run --rm hello-world\n"
fi

echo
done_ "Docker Engine + Compose installed and ready"

script_finish "0"
