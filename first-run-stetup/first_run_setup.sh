#!/usr/bin/env bash
# ============================================================
# first_run_setup.sh — Initial system update after clean install
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
_SCRIPT_TITLE=""
_SCRIPT_STARTED=0

# ── Run banner ────────────────────────────────────────────────
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
success() { printf "  ${GREEN}${ICO_OK}${NC}  %s\n" "$1"; }
fail()    { printf "  ${RED}${ICO_FAIL}${NC}  %s\n" "$1" >&2; }
info()    { printf "  ${CYAN}${ICO_INFO}${NC}  %s\n" "$1"; }
warn()    { printf "  ${YELLOW}${ICO_WARN}${NC}  %s\n" "$1"; }
step()    { printf "\n  ${CYAN}${BOLD}${ICO_STEP}${NC}  ${BOLD}%s${NC}\n" "$1"; }

# ── Spinner ───────────────────────────────────────────────────
_SPIN_PID=""
spin_start() {
  # Only spin when writing to a real terminal; skip in log-only mode
  if [[ -t 1 ]]; then
    local msg="$1"
    (while true; do
      for c in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
        printf "\r  %s  ${DIM}%s${NC} " "$c" "$msg"; sleep 0.1
      done
    done) &
    _SPIN_PID=$!
  else
    info "$1"
  fi
}
spin_stop() {
  if [[ -n "$_SPIN_PID" ]]; then
    kill "$_SPIN_PID" 2>/dev/null || true
    wait "$_SPIN_PID" 2>/dev/null || true
    _SPIN_PID=""
  fi
  [[ -t 1 ]] && printf "\r\033[2K" || true
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

# ── Helpers ───────────────────────────────────────────────────
require_root() {
  [[ $EUID -eq 0 ]] || { fail "This script must be run as root (use sudo)."; exit 1; }
}

# ── Configuration ─────────────────────────────────────────────
LOG_FILE="/var/log/first_run_setup.log"

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
require_root

# Script messages visible on console; full output also written to log file
exec > >(tee -a "$LOG_FILE") 2>&1

script_start "First-Run System Update" "log=${LOG_FILE}"

# ── 1. Update package index ───────────────────────────────────
step "Updating package index"
spin_start "Running apt-get update (this may take a while)..."
  apt-get update
spin_stop
success "\nPackage index updated"

# ── 2. Upgrade installed packages ────────────────────────────
step "Upgrading installed packages"
spin_start "Running apt-get upgrade (this may take a while)..."
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
spin_stop
success "All packages upgraded"

# ── 3. Dist-upgrade (kernel + held packages) ─────────────────
step "Applying dist-upgrade"
spin_start "Running apt-get dist-upgrade (this may take a while)..."
  DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
spin_stop
success "dist-upgrade complete"

# ── 4. Cleanup ────────────────────────────────────────────────
step "Cleaning up"

spin_start "Removing orphaned packages..."
  apt-get autoremove -y
spin_stop
success "Orphaned packages removed"

spin_start "Cleaning package cache..."
  apt-get autoclean
spin_stop
success "Package cache cleaned"

# ── 5. Reboot check ───────────────────────────────────────────
step "Checking if reboot is required"
if [[ -f /var/run/reboot-required ]]; then
  warn "Reboot required — a kernel or core library was upgraded."
  warn "Run: ${YELLOW}sudo reboot${NC}"
else
  success "No reboot required"
fi

script_finish "0"
