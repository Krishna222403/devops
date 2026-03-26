#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
GRAFANA_VERSION="11.1.4"
PROMETHEUS_IP=""
GRAFANA_ADMIN_PASS=""

echo "=========================================="
echo " Grafana Machine Setup"
echo "=========================================="
log_info "This machine will:"
log_info "  - Install Grafana Enterprise ${GRAFANA_VERSION}"
log_info "  - Configure Prometheus as data source"
log_info "  - Expose Grafana UI on port 3000"
echo ""

# Get configuration from user
read -p "Enter Prometheus machine IP (for data source): " PROMETHEUS_IP
if [ -z "$PROMETHEUS_IP" ]; then
    log_error "Prometheus machine IP is required"
    exit 1
fi

read -p "Set Grafana admin password (leave empty for default 'admin'): " GRAFANA_ADMIN_PASS
# If empty, we'll leave default password (admin/admin)

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
        return 0
    else
        log_error "This script requires sudo privileges"
        exit 1
    fi
}

# Function: Install Grafana
install_grafana() {
    check_privileges
    log_info "Starting Grafana installation..."

    # Download Grafana
    GRAFANA_TAR="grafana-enterprise-${GRAFANA_VERSION}.linux-amd64.tar.gz"
    log_info "Downloading Grafana Enterprise ${GRAFANA_VERSION}..."
    wget "https://dl.grafana.com/enterprise/release/${GRAFANA_TAR}" -O "/tmp/${GRAFANA_TAR}"

    # Extract
    log_info "Extracting Grafana..."
    tar -zxvf "/tmp/${GRAFANA_TAR}" -C /opt/

    # Handle both naming conventions (with or without 'v')
    EXTRACTED_DIR=$(find /opt -maxdepth 1 -type d -name "grafana*${GRAFANA_VERSION}*" | head -n 1)
    if [ -n "$EXTRACTED_DIR" ]; then
        sudo mv "$EXTRACTED_DIR" /opt/grafana
    else
        log_error "Could not find extracted Grafana directory"
        exit 1
    fi

    # Clean up
    rm "/tmp/${GRAFANA_TAR}"

    # Create Grafana service
    log_info "Creating Grafana systemd service..."
    cat <<EOF | sudo tee /etc/systemd/system/grafana.service > /dev/null
[Unit]
Description=Grafana service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/grafana/bin/grafana-server --config=/opt/grafana/conf/defaults.ini --homepath=/opt/grafana --packaging=deb
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create data directory if it doesn't exist
    sudo mkdir -p /var/lib/grafana
    sudo chown -R root:root /var/lib/grafana

    # Reload systemd and start Grafana
    log_info "Starting Grafana service..."
    sudo systemctl daemon-reload
    sudo systemctl enable grafana
    sudo systemctl start grafana

    sleep 5
    sudo systemctl status grafana --no-pager -n 3

    # Verify Grafana is working
    log_info "Verifying Grafana is accessible..."
    sleep 5
    if curl -s http://localhost:3000/api/health > /dev/null; then
        log_info "✓ Grafana is ready at http://localhost:3000"
    else
        log_warn "Grafana may still be starting..."
    fi

    # Configure Prometheus data source via Grafana API (if possible)
    # Note: This requires Grafana to be fully started and may need API key
    log_info "Grafana installed. You'll need to configure Prometheus data source manually:"
    echo ""
    echo "To configure Prometheus data source:"
    echo "  1. Login to Grafana at http://<grafana-ip>:3000"
    echo "     - Username: admin"
    echo "     - Password: ${GRAFANA_ADMIN_PASS:-admin (change on first login)}"
    echo "  2. Go to Configuration (gear icon) → Data Sources"
    echo "  3. Click 'Add data source' → select Prometheus"
    echo "  4. Configure:"
    echo "     - Name: Prometheus"
    echo "     - URL: http://${PROMETHEUS_IP}:9090"
    echo "  5. Click 'Save & Test'"
    echo ""
    echo "Optional: Create API key for automation:"
    echo "  - In Grafana: Configuration → API Keys → Create new key"
    echo ""

    echo ""
    echo "=========================================="
    echo " Grafana Machine Setup Complete!"
    echo "=========================================="
    echo ""
    echo "Grafana version: ${GRAFANA_VERSION}"
    echo ""
    echo "Configuration:"
    echo "  - Grafana UI: http://<this-machine-ip>:3000"
    echo "  - Prometheus data source: http://${PROMETHEUS_IP}:9090"
    echo ""
    echo "Default credentials:"
    if [ -z "$GRAFANA_ADMIN_PASS" ]; then
        echo "  - Username: admin"
        echo "  - Password: admin (CHANGE ON FIRST LOGIN)"
    else
        echo "  - Username: admin"
        echo "  - Password: [your custom password]"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Access Grafana at: http://<this-machine-ip>:3000"
    echo "  2. Login and add Prometheus data source (instructions above)"
    echo "  3. Import dashboard (e.g., Docker monitoring: ID 6417)"
    echo "=========================================="
}

# Main execution
check_privileges
install_grafana