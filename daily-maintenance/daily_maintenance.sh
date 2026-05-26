#!/usr/bin/env bash
# ============================================================
# daily_maintenance.sh — Daily system maintenance & cleanup
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

# ── Helpers ───────────────────────────────────────────────────
# Returns human-readable size of a path (or 0B if missing)
_du() { du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"; }

# Prints RAM info line
_ram_info() {
  local free_mb total_mb
  free_mb=$(awk '/^MemAvailable:/ { printf "%d", $2/1024 }' /proc/meminfo)
  total_mb=$(awk '/^MemTotal:/     { printf "%d", $2/1024 }' /proc/meminfo)
  echo "${free_mb} MB free / ${total_mb} MB total"
}

# ── Configuration ─────────────────────────────────────────────
TMP_MAX_DAYS=7          # files in /tmp older than this are removed
VAR_TMP_MAX_DAYS=14     # files in /var/tmp older than this are removed
JOURNAL_MAX_DAYS="30d"  # journald retention period
OLD_LOG_DAYS=90         # compress/remove rotated logs older than this
CRASH_DIR="/var/crash"  # Ubuntu crash reports directory
THUMBNAIL_DIRS=(        # per-user thumbnail caches
  /root/.cache/thumbnails
  /home/*/.cache/thumbnails
)
LOG_FILE="/var/log/daily_maintenance.log"

# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════
require_root

# Redirect a copy of all output to the log file
exec > >(tee -a "$LOG_FILE") 2>&1

script_start "Daily System Maintenance" "$(date '+%Y-%m-%d %H:%M:%S')"

info "Log file: ${YELLOW}${LOG_FILE}${NC}"

# ─────────────────────────────────────────────────────────────
# 1. DISK USAGE SNAPSHOT — before
# ─────────────────────────────────────────────────────────────
step "Disk usage — before cleanup"
df -h / | awk 'NR==2 { printf "  '"${CYAN}"'%-10s'"${NC}"'  used: '"${YELLOW}"'%s'"${NC}"'  avail: '"${GREEN}"'%s'"${NC}"'  (%s)\n", $1, $3, $4, $5 }'
echo

# ─────────────────────────────────────────────────────────────
# 2. RAM CACHE
# ─────────────────────────────────────────────────────────────
step "Freeing page cache, dentries & inodes"
info "RAM before: $(_ram_info)"

spin_start "Syncing filesystems..."
  sync
spin_stop
success "Filesystems synced"

# Drop: 1=page cache, 2=dentries+inodes, 3=both
echo 3 > /proc/sys/vm/drop_caches
success "Page cache, dentries and inodes dropped"
info "RAM after:  $(_ram_info)"

# Compact memory (reduces fragmentation, available on kernel >= 3.1)
if [[ -f /proc/sys/vm/compact_memory ]]; then
  echo 1 > /proc/sys/vm/compact_memory
  success "Memory compaction triggered"
else
  skip "Memory compaction (kernel flag not available)"
fi

# ─────────────────────────────────────────────────────────────
# 3. SWAP
# ─────────────────────────────────────────────────────────────
step "Refreshing swap space"
SWAP_TOTAL=$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)
if [[ "$SWAP_TOTAL" -gt 0 ]]; then
  info "Swap before: $(free -h | awk '/^Swap:/ {print $3 " used / " $2 " total"}')"
  spin_start "Cycling swap off -> on..."
    swapoff -a
    swapon -a
  spin_stop
  success "Swap recycled"
  info "Swap after:  $(free -h | awk '/^Swap:/ {print $3 " used / " $2 " total"}')"
else
  skip "No swap configured"
fi

# ─────────────────────────────────────────────────────────────
# 4. /tmp CLEANUP
# ─────────────────────────────────────────────────────────────
step "Cleaning /tmp (files older than ${TMP_MAX_DAYS} days)"
TMP_BEFORE=$(_du /tmp)
spin_start "Removing old files from /tmp..."
  find /tmp -mindepth 1 -atime +"$TMP_MAX_DAYS" -delete 2>/dev/null || true
spin_stop
TMP_AFTER=$(_du /tmp)
success "/tmp cleaned  (${TMP_BEFORE} -> ${TMP_AFTER})"

# ─────────────────────────────────────────────────────────────
# 5. /var/tmp CLEANUP
# ─────────────────────────────────────────────────────────────
step "Cleaning /var/tmp (files older than ${VAR_TMP_MAX_DAYS} days)"
VTMP_BEFORE=$(_du /var/tmp)
spin_start "Removing old files from /var/tmp..."
  find /var/tmp -mindepth 1 -atime +"$VAR_TMP_MAX_DAYS" -delete 2>/dev/null || true
spin_stop
VTMP_AFTER=$(_du /var/tmp)
success "/var/tmp cleaned  (${VTMP_BEFORE} -> ${VTMP_AFTER})"

# ─────────────────────────────────────────────────────────────
# 6. APT PACKAGE CACHE
# ─────────────────────────────────────────────────────────────
step "Cleaning APT package cache"
if command -v apt-get &>/dev/null; then
  APT_BEFORE=$(_du /var/cache/apt/archives)
  spin_start "Running apt-get autoremove & autoclean..."
    apt-get -y autoremove --purge -qq
    apt-get autoclean -qq
    apt-get clean -qq
  spin_stop
  APT_AFTER=$(_du /var/cache/apt/archives)
  success "APT cache cleaned  (${APT_BEFORE} -> ${APT_AFTER})"
else
  skip "apt-get not found — skipping APT cleanup"
fi

# ─────────────────────────────────────────────────────────────
# 7. JOURNALD LOG VACUUM
# ─────────────────────────────────────────────────────────────
step "Vacuuming systemd journal (keep last ${JOURNAL_MAX_DAYS})"
if command -v journalctl &>/dev/null; then
  JRNL_BEFORE=$(_du /var/log/journal)
  spin_start "Running journalctl --vacuum-time=${JOURNAL_MAX_DAYS}..."
    journalctl --vacuum-time="$JOURNAL_MAX_DAYS" --quiet 2>&1 || true
  spin_stop
  JRNL_AFTER=$(_du /var/log/journal)
  success "Journal vacuumed  (${JRNL_BEFORE} -> ${JRNL_AFTER})"
else
  skip "journalctl not found"
fi

# ─────────────────────────────────────────────────────────────
# 8. OLD ROTATED LOGS
# ─────────────────────────────────────────────────────────────
step "Removing rotated logs older than ${OLD_LOG_DAYS} days"
spin_start "Scanning /var/log for old .gz / .old logs..."
  find /var/log -type f \( -name "*.gz" -o -name "*.old" -o -name "*.[0-9]" \) \
    -mtime +"$OLD_LOG_DAYS" -delete 2>/dev/null || true
spin_stop
success "Old rotated logs removed"

# Force log rotation for anything overdue
if command -v logrotate &>/dev/null; then
  spin_start "Running logrotate..."
    logrotate -f /etc/logrotate.conf 2>/dev/null || true
  spin_stop
  success "logrotate forced"
else
  skip "logrotate not found"
fi

# ─────────────────────────────────────────────────────────────
# 9. CRASH REPORTS
# ─────────────────────────────────────────────────────────────
step "Clearing crash reports in ${CRASH_DIR}"
if [[ -d "$CRASH_DIR" ]]; then
  CRASH_COUNT=$(find "$CRASH_DIR" -maxdepth 1 -type f | wc -l)
  if [[ "$CRASH_COUNT" -gt 0 ]]; then
    rm -f "${CRASH_DIR}"/*.crash 2>/dev/null || true
    rm -f "${CRASH_DIR}"/*.lock  2>/dev/null || true
    success "Removed ${CRASH_COUNT} crash report(s)"
  else
    skip "No crash reports found"
  fi
else
  skip "${CRASH_DIR} does not exist"
fi

# ─────────────────────────────────────────────────────────────
# 10. THUMBNAIL CACHES
# ─────────────────────────────────────────────────────────────
step "Clearing thumbnail caches"
for dir in "${THUMBNAIL_DIRS[@]}"; do
  # glob may not expand — check each real match
  for expanded in $dir; do
    if [[ -d "$expanded" ]]; then
      THUMB_BEFORE=$(_du "$expanded")
      rm -rf "${expanded:?}"/* 2>/dev/null || true
      success "Cleared ${expanded}  (was ${THUMB_BEFORE})"
    fi
  done
done || true

# ─────────────────────────────────────────────────────────────
# 11. OLD CORE DUMPS
# ─────────────────────────────────────────────────────────────
step "Removing core dumps"
CORE_COUNT=0
while IFS= read -r -d '' core; do
  rm -f "$core" 2>/dev/null || true
  CORE_COUNT=$(( CORE_COUNT + 1 ))
done < <(find / \( -path /proc -o -path /sys \) -prune \
           -o -type f -name "core" -print0 \
           -o -type f -name "core.[0-9]*" -print0 2>/dev/null) || true

if [[ "$CORE_COUNT" -gt 0 ]]; then
  success "Removed ${CORE_COUNT} core dump(s)"
else
  skip "No core dumps found"
fi

# ─────────────────────────────────────────────────────────────
# 12. FAILED SYSTEMD UNITS
# ─────────────────────────────────────────────────────────────
step "Checking for failed systemd units"
if command -v systemctl &>/dev/null; then
  FAILED_UNITS=$(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null \
                 | awk '{print $1}' | tr '\n' ' ')
  if [[ -n "$FAILED_UNITS" ]]; then
    warn "Failed units detected: ${FAILED_UNITS}"
    info "Run: systemctl reset-failed  to acknowledge after investigation"
  else
    success "No failed systemd units"
  fi
  # Reset acknowledged failures (harmless if none)
  systemctl reset-failed 2>/dev/null || true
else
  skip "systemctl not available"
fi

# ─────────────────────────────────────────────────────────────
# 13. ORPHANED PACKAGES (Debian/Ubuntu only)
# ─────────────────────────────────────────────────────────────
step "Checking for orphaned packages"
if command -v deborphan &>/dev/null; then
  ORPHANS=$(deborphan 2>/dev/null | tr '\n' ' ')
  if [[ -n "$ORPHANS" ]]; then
    warn "Orphaned packages found: ${ORPHANS}"
    info "Remove with: apt-get purge \$(deborphan)"
  else
    success "No orphaned packages"
  fi
else
  skip "deborphan not installed — install with apt-get install deborphan"
fi

# ─────────────────────────────────────────────────────────────
# 14. DISK USAGE SNAPSHOT — after
# ─────────────────────────────────────────────────────────────
step "Disk usage — after cleanup"
df -h / | awk 'NR==2 { printf "  '"${CYAN}"'%-10s'"${NC}"'  used: '"${YELLOW}"'%s'"${NC}"'  avail: '"${GREEN}"'%s'"${NC}"'  (%s)\n", $1, $3, $4, $5 }'
echo

# ─────────────────────────────────────────────────────────────
# 15. SUMMARY
# ─────────────────────────────────────────────────────────────
done_ "All maintenance tasks completed — see ${LOG_FILE} for full log"

script_finish "0"
