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

FIREWALL="🛡️"
NETWORK="🌐"
BAN="⛔"

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
print_info "This script will install and configure UFW and Fail2Ban on your Raspberry Pi."
print_warn "Ensure all required variables are set before running this script."

# ===== PRECHECKS =============================================================
print_step "Checking privileges"
if [[ $EUID -ne 0 ]]; then
    print_warn "Please run with sudo"
    exit 1
fi
print_ok "Running as root"

# ===== INSTALL UFW ===========================================================
print_step "Installing UFW"
sudo apt update && sudo apt install -y ufw
print_ok "UFW installed"

# ===== RESET UFW =============================================================
print_step "Resetting UFW rules"
sudo ufw --force reset
print_ok "UFW reset done"

# ===== DEFAULT POLICY ========================================================
print_step "Setting default policies"
sudo ufw default deny incoming
sudo ufw default allow outgoing
print_ok "Default policies applied"

# ===== ENABLE LOGGING ========================================================
print_step "Enabling UFW logging"
sudo ufw logging on
print_ok "Logging enabled"

# ===== RATE LIMIT SSH ========================================================
print_step "Adding SSH rate limiting on port 22"
sudo ufw limit 22/tcp
print_ok "SSH rate limiting applied (password login still allowed)"

# ===== ALLOW SPECIFIC PORTS FROM SUBNET =====================================

print_step "Allowing SSH from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 22 proto tcp

print_step "Allowing HTTP from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 80 proto tcp

print_step "Allowing HTTPS from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 443 proto tcp

print_step "Allowing Nextcloud from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 9060 proto tcp

print_step "Allowing Home Assistant from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 9070 proto tcp

print_step "Allowing code-server from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 9080 proto tcp

print_step "Allowing Prometheus from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 9090 proto tcp

print_step "Allowing Prometheus from Docker bridge network (172.17.0.0/16)"
sudo ufw allow from 172.17.0.0/16 to any port 9090 proto tcp

print_step "Allowing node_exporter from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 9100 proto tcp

print_step "Allowing Portainer from 192.168.0.0/16"
sudo ufw allow from "192.168.0.0/16" to any port 9443 proto tcp

# ===== ENABLE UFW ============================================================
print_step "Enabling UFW"
sudo ufw --force enable
print_ok "UFW is active"

# ===== INSTALL FAIL2BAN ======================================================
print_step "Installing Fail2Ban"
sudo apt install -y fail2ban
print_ok "Fail2Ban installed"

# ===== BASIC FAIL2BAN CONFIG =================================================
print_step "Creating basic Fail2Ban configuration"
F2B_LOCAL="/etc/fail2ban/jail.local"

sudo tee "$F2B_LOCAL" >/dev/null <<EOL
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
destemail = blaz.baskovc@gmail.com
sender = fail2ban@localhost
mta = sendmail
action = %(action_mwl)s

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log

[portainer]
enabled = true
port = 9443
filter = generic-proto
logpath = /var/log/syslog
EOL

# ===== RESTART FAIL2BAN =====================================================
print_step "Restarting Fail2Ban to apply configuration"
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
print_ok "Fail2Ban is active and running"
print_ok "\n${GREEN}${BOLD}✔ Server is now secured with UFW + Fail2Ban${RESET}"

# ===== STATUS =================================================================
print_ok "Firewall and Fail2Ban setup complete."
print_ok "UFW status:"
sudo ufw status verbose
print_ok "Fail2Ban status:"
sudo fail2ban-client status

print_ok "\n${GREEN}${BOLD}✔ Server is now secured with UFW + Fail2Ban${RESET}\n"
