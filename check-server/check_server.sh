#!/usr/bin/env bash
# ============================================================
# check_server.sh — Check if a remote server is alive
# Author : gen-shell-script
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

# ── Timing ────────────────────────────────────────────────────
_T_START="${EPOCHREALTIME:-$SECONDS}"
_elapsed() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    awk "BEGIN { printf \"%.3f\", ${EPOCHREALTIME} - ${_T_START} }"
  else
    echo $(( SECONDS - ${_T_START%.*} ))
  fi
}

# ── Script path (relative to cwd) ────────────────────────────
_SCRIPT_REL=$(realpath --relative-to="$(pwd)" "${BASH_SOURCE[0]}" 2>/dev/null \
              || echo "${BASH_SOURCE[0]}")

# ── Script state (set by script_start) ─────────────────────────
_SCRIPT_TITLE=""
_SCRIPT_STARTED=0

# ── Run banner (optional title shown above script path) ──────
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

# ── Normal finish — EXIT trap prints the footer ───────────────────
script_finish() {
  exit "${1:-0}"
}

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

# ── Exit handler — fires on ANY exit, always prints footer ────────────
_on_exit() {
  local code=$?
  set +e  # prevent set -e from interfering inside this handler
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

# ── Error trap — prints inline error context, EXIT trap prints footer ────
_on_error() {
  spin_stop
  printf "\n  ❌  ${RED}Error at line %s${NC} (exit code ${RED}%s${NC})\n" "$1" "$2"
  exit "$2"
}
trap '_on_error $LINENO $?' ERR

# ── Configuration ─────────────────────────────────────────────
HOST="${1:-}"                       # positional arg or set here
PING_COUNT=3                        # ICMP packets to send
PING_TIMEOUT=2                      # seconds per ping
TCP_TIMEOUT=3                       # seconds for TCP port check
# Ports to probe: "port:label"
PORTS=(
  "22:SSH"
  "80:HTTP"
  "443:HTTPS"
)

# ── Usage ─────────────────────────────────────────────────────
usage() {
  printf "\n${BOLD}Usage:${NC}  %s <host> [port:label ...]\n" "$(basename "$0")"
  printf "        %s 192.168.1.1\n" "$(basename "$0")"
  printf "        %s myserver.com 22:SSH 5432:PostgreSQL\n\n" "$(basename "$0")"
  exit 1
}

[[ -z "$HOST" ]] && { fail "No host specified."; usage; }

# Override port list if extra args are provided
if [[ $# -gt 1 ]]; then
  PORTS=("${@:2}")
fi

# ── Prerequisites ─────────────────────────────────────────────
for cmd in ping nc; do
  command -v "$cmd" &>/dev/null || { fail "Required tool not found: $cmd"; exit 1; }
done

# ─────────────────────────────────────────────────────────────

script_start "Server Health Check" "${HOST}"

# ── Resolve hostname ──────────────────────────────────────────
step "Resolving hostname"
spin_start "Looking up ${HOST}..."
  resolved_ip=$(getent hosts "$HOST" 2>/dev/null | awk '{print $1; exit}' || true)
spin_stop

if [[ -n "$resolved_ip" ]]; then
  success "Resolved: ${HOST} → ${resolved_ip}"
else
  # Could be a bare IP; check it's syntactically valid
  if [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    resolved_ip="$HOST"
    info "Using IP address directly: ${resolved_ip}"
  else
    fail "Cannot resolve hostname: ${HOST}"
    exit 1
  fi
fi

# ── ICMP Ping ─────────────────────────────────────────────────
step "Ping test (ICMP)"
spin_start "Sending ${PING_COUNT} ping(s) to ${HOST}..."
  ping_output=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$HOST" 2>&1 || true)
  # Strip any ANSI color codes ping may emit
  ping_output=$(printf '%s' "$ping_output" | sed 's/\x1b\[[0-9;]*m//g')
spin_stop

if echo "$ping_output" | grep -q "0 received\|100% packet loss\|unknown host"; then
  fail "Host is NOT reachable via ICMP (ping failed)"
  PING_STATUS="DOWN"
else
  # Extract round-trip average
  rtt=$(echo "$ping_output" | grep -oP 'rtt.*= \K[0-9.]+(?=/[0-9.]+/[0-9.]+/[0-9.]+)' || echo "?")
  success "ICMP reachable  (avg RTT: ${rtt} ms)"
  PING_STATUS="UP"
fi

# ── TCP Port Checks ───────────────────────────────────────────
step "TCP port checks"

PORTS_UP=0
PORTS_DOWN=0
TOTAL_PORTS=${#PORTS[@]}

progress() {
  local cur=$1 tot=$2 lbl="${3:-}"
  local pct=$(( cur * 100 / tot ))
  local filled=$(( cur * 30 / tot ))
  local bar=""
  for (( i=0; i<filled; i++ ));  do bar+="█"; done
  for (( i=filled; i<30; i++ )); do bar+="░"; done
  printf "\r  ${CYAN}[%s]${NC} %3d%% %s" "$bar" "$pct" "$lbl"
}

for i in "${!PORTS[@]}"; do
  entry="${PORTS[$i]}"
  port="${entry%%:*}"
  label="${entry##*:}"

  progress $(( i + 1 )) "$TOTAL_PORTS" "Scanning ports..."

  if nc -z -w "$TCP_TIMEOUT" "$HOST" "$port" 2>/dev/null; then
    printf "\r\033[2K  ${GREEN}${ICO_OK}${NC}  Port ${BOLD}%-6s${NC}  ${DIM}%-12s${NC}  ${GREEN}OPEN${NC}\n" \
      "$port" "$label"
    PORTS_UP=$(( PORTS_UP + 1 ))
  else
    printf "\r\033[2K  ${RED}${ICO_FAIL}${NC} Port ${BOLD}%-6s${NC}  ${DIM}%-12s${NC}  ${RED}CLOSED / FILTERED${NC}\n" \
      "$port" "$label"
    PORTS_DOWN=$(( PORTS_DOWN + 1 ))
  fi
done

# ── Summary ───────────────────────────────────────────────────
step "Summary"
info  "Host         : ${YELLOW}${HOST}${NC} (${resolved_ip})"

if [[ "$PING_STATUS" == "UP" ]]; then
  success "ICMP ping    : ALIVE"
else
  fail    "ICMP ping    : UNREACHABLE"
fi

[[ $PORTS_UP   -gt 0 ]] && success "Ports open   : ${PORTS_UP} / ${TOTAL_PORTS}"
[[ $PORTS_DOWN -gt 0 ]] && warn    "Ports closed : ${PORTS_DOWN} / ${TOTAL_PORTS}"

# Overall verdict
echo
if [[ "$PING_STATUS" == "UP" || "$PORTS_UP" -gt 0 ]]; then
  printf "  ${GREEN}${BOLD}SERVER IS ALIVE${NC}\n"
  EXIT_CODE=0
else
  printf "  ${RED}${BOLD}SERVER APPEARS DOWN${NC}\n"
  EXIT_CODE=1
fi

script_finish "$EXIT_CODE"
exit "$EXIT_CODE"
