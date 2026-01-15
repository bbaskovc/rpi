#!/usr/bin/env bash

set -e

# ===== CONFIG ================================================================
NODE_EXPORTER_VERSION="1.10.2"
ARCH="linux-arm64"
DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz"
TMP_DIR="/tmp/node_exporter_install"

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
print_info "This script will install Prometheus Node Exporter and its dependencies on your system."
print_warn "It will download and install the node_exporter binary, and set up a systemd service."

# ===== PRECHECKS =============================================================
print_step "Checking privileges"
if [[ $EUID -ne 0 ]]; then
    print_warn "Please run with sudo"
    exit 1
fi
print_ok "Running as root"

# ===== DOWNLOAD & INSTALL ====================================================
print_step "Installing node_exporter v${NODE_EXPORTER_VERSION}"
sudo mkdir -p "$TMP_DIR"
cd "$TMP_DIR"
wget -q "$DOWNLOAD_URL" -O node_exporter.tar.gz
tar xzf node_exporter.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}/node_exporter /usr/local/bin/
sudo chown root:root /usr/local/bin/node_exporter
sudo chmod 755 /usr/local/bin/node_exporter
cd ~
sudo rm -rf "$TMP_DIR"

print_ok "node_exporter binary installed to /usr/local/bin/node_exporter"

# ===== CREATE SYSTEMD SERVICE ================================================
print_step "Creating systemd service for node_exporter"
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<EOL
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

print_ok "node_exporter service started and enabled"
print_ok "Metrics available at http://$(hostname -I | awk '{print $1}'):9100/metrics"
print_ok "Metrics available at http://$(hostname -I | awk '{print $1}'):9100/metrics"
