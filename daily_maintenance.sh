#!/usr/bin/env bash

set -e

# ===== ANSI COLORS & ICONS ====================================================
RESET="\033[0m"
BOLD="\033[1m"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"

OK="${GREEN}✔${RESET}"
ERR="${RED}✖${RESET}"
INFO="${BLUE}ℹ${RESET}"
WARN="${YELLOW}⚠${RESET}"
RUN="${CYAN}➜${RESET}"

RAM="🧠"
DISK="💽"
DOCKER="🐳"
LOGS="🧾"
PKG="📦"
TRIM="✂"
CLOCK="⏰"


# ===== HELPERS ===============================================================
print_step() {
    echo -e "\n${BOLD}${RUN} $1${RESET}"
}

print_ok() {
    echo -e "${OK} $1"
}

print_warn() {
    echo -e "${WARN} $1"
}

print_info() {
    echo -e "${INFO} $1"
}

# ===== SCRIPT START ==========================================================
print_info "Starting daily maintenance tasks."
print_warn "Ensure all required scripts and dependencies are available before proceeding."

# ===== PRECHECKS =============================================================
print_step "Checking privileges"
if [[ $EUID -ne 0 ]]; then
    print_warn "Please run with sudo"
    exit 1
fi
print_ok "Running as root"

# ===== TIME SYNC CHECK ======================================================
print_step "Checking time synchronization status"
if systemctl is-active --quiet systemd-timesyncd; then
    print_ok "systemd-timesyncd is active (time is synchronized)"
    last_sync=$(timedatectl show-timesync --value --property=ServerReachable 2>/dev/null)
    if timedatectl show-timesync --all 2>/dev/null | grep -q 'LastSync'; then
        last_sync_time=$(timedatectl show-timesync --all 2>/dev/null | grep 'LastSync' | awk -F= '{print $2}')
        print_info "Last time sync: $last_sync_time"
    fi
elif systemctl is-active --quiet ntp; then
    print_ok "ntpd service is active (time is synchronized)"
    if command -v ntpq >/dev/null 2>&1; then
        last_ntp_sync=$(ntpq -c rv 2>/dev/null | grep 'sync' | head -n1)
        print_info "NTP status: $last_ntp_sync"
    fi
elif systemctl is-active --quiet chronyd; then
    print_ok "chronyd service is active (time is synchronized)"
    if command -v chronyc >/dev/null 2>&1; then
        last_chrony_sync=$(chronyc tracking 2>/dev/null | grep 'Last offset')
        print_info "Chrony: $last_chrony_sync"
    fi
else
    print_warn "No active NTP or time sync service detected!"
fi

# ===== SYNC FILESYSTEM ========================================================
print_step "${DISK} Syncing filesystem"
sync
print_ok "Filesystem synced"

# ===== DROP CACHES ===========================================================
print_step "${RAM} Dropping filesystem caches"
echo 3 | tee /proc/sys/vm/drop_caches >/dev/null
print_ok "Caches dropped"

# ===== MEMORY COMPACTION =====================================================
print_step "${RAM} Compacting memory"
echo 1 | tee /proc/sys/vm/compact_memory >/dev/null
print_ok "Memory compacted"

# ===== ZRAM / SWAP REFRESH ===================================================
print_step "${RAM} Refreshing swap (zram)"
swapoff -a
swapon -a
print_ok "Swap refreshed"

# ===== DOCKER CLEANUP ========================================================
if command -v docker >/dev/null 2>&1; then
    print_step "${DOCKER} Cleaning unused Docker data"
    docker system prune -af --volumes
    print_ok "Docker cleaned"
else
    print_warn "Docker not installed"
fi

# ===== APT CLEANUP ===========================================================
print_step "${PKG} Cleaning APT cache"
apt clean
apt autoremove -y
print_ok "APT cleanup done"

# ===== LOG ROTATION ==========================================================
print_step "${LOGS} Rotating system logs"
logrotate -f /etc/logrotate.conf
print_ok "Logs rotated"

# ===== TRIM STORAGE ==========================================================
if command -v fstrim >/dev/null 2>&1; then
    print_step "${TRIM} Trimming filesystems"
    fstrim -av
    print_ok "Trim completed"
else
    print_warn "fstrim not available"
fi

echo -e "\n${GREEN}${BOLD}✔ Daily maintenance completed successfully${RESET}\n"
# ===== STATUS ================================================================
print_info "${RAM} Memory status:"
free -h

print_ok "\n${GREEN}${BOLD}✔ Daily maintenance completed successfully${RESET}"
