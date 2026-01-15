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
print_info "This script will install Docker Engine and its dependencies on your system."
print_warn "It will update your system and may require a reboot after completion."

# ===== PRECHECKS =============================================================
print_step "Checking privileges"
if [[ $EUID -ne 0 ]]; then
    echo -e "${ERR} Please run with sudo"
    exit 1
fi
print_ok "Running as root"

USER_NAME=${SUDO_USER:-$(whoami)}

# ===== SYSTEM UPDATE ==========================================================
print_step "Updating system packages"
apt update -y
apt full-upgrade -y
print_ok "System updated"

# ===== DEPENDENCIES ===========================================================
print_step "Installing required packages"
apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
print_ok "Dependencies installed"

# ===== DOCKER INSTALL =========================================================
print_step "Installing Docker using official script"
curl -fsSL https://get.docker.com | sh
print_ok "Docker installed"

# ===== USER GROUP =============================================================
print_step "Adding user '${USER_NAME}' to docker group"
usermod -aG docker "${USER_NAME}"
print_ok "User added to docker group"

print_step "Adding user 'admin' to docker group"
usermod -aG docker "admin"
print_ok "User added to docker group (log out/in to apply)"

# ===== ENABLE SERVICES ========================================================
print_step "Enabling Docker service at boot"
systemctl enable docker
systemctl start docker
print_ok "Docker service running"

# ===== TEST ===================================================================
print_step "Verifying Docker installation"
docker --version && print_ok "Docker CLI works"

# ===== FINISH =================================================================
echo -e "\n${GREEN}${BOLD}🎉 Docker installation complete!${RESET}"
echo -e "${INFO} Log out and log back in (or reboot) to use Docker without sudo"
echo -e "${INFO} Test with: ${BOLD}docker run hello-world${RESET}\n"
