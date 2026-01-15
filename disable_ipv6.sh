#!/usr/bin/env bash

set -e

# ===== ANSI COLORS & ICONS ====================================================
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RED="\033[31m"

OK="${GREEN}✔${RESET}"
ERR="${RED}✖${RESET}"
INFO="${BLUE}ℹ${RESET}"
WARN="${YELLOW}⚠${RESET}"
RUN="${CYAN}➜${RESET}"

IPV6="🌐"

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
print_info "This script will permanently disable IPv6 on your system."
print_warn "Disabling IPv6 may affect applications or services that rely on it."

# ===== PRECHECKS =============================================================
print_step "Checking privileges"
if [[ $EUID -ne 0 ]]; then
    echo -e "${ERR} Please run with sudo"
    exit 1
fi
print_ok "Running as root"

# ===== CREATE SYSCONFIG FILE =================================================
SYSCTL_FILE="/etc/sysctl.d/99-disable-ipv6.conf"
print_step "Creating sysctl config file: ${SYSCTL_FILE}"
sudo tee "$SYSCTL_FILE" >/dev/null <<EOL
# Disable IPv6 permanently
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOL
print_ok "Sysctl config created"

# ===== APPLY IMMEDIATELY ====================================================
print_step "Applying sysctl settings now"
sudo sysctl --system
print_ok "IPv6 disabled temporarily (applied immediately)"

# ===== VERIFY ===============================================================
print_step "Verifying IPv6 status"
if ip a | grep inet6; then
    print_warn "IPv6 addresses still detected (check config)"
else
    print_ok "No IPv6 addresses detected"
fi

echo -e "\n${GREEN}${BOLD}✔ IPv6 is now permanently disabled${RESET}\n"
