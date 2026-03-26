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
PROMETHEUS_VERSION="2.53.2"
GRAFANA_IP=""
DOCKER_MACHINE_IP=""

echo "=========================================="
echo " Prometheus Machine Setup"
echo "=========================================="
log_info "This machine will:"
log_info "  - Install Prometheus ${PROMETHEUS_VERSION}"
log_info "  - Scrape metrics from Docker machine"
log_info "  - Expose Prometheus UI on port 9090"
echo ""

# Get configuration from user
read -p "Enter Docker machine IP (for metrics scraping): " DOCKER_MACHINE_IP
if [ -z "$DOCKER_MACHINE_IP" ]; then
    log_error "Docker machine IP is required"
    exit 1
fi

read -p "Enter Grafana machine IP (for integration): " GRAFANA_IP
if [ -z "$GRAFANA_IP" ]; then
    log_error "Grafana machine IP is required"
    exit 1
fi

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
        return 0
    else
        log_error "This script requires sudo privileges"
        exit 1
    fi
}

# Function: Install Prometheus
install_prometheus() {
    check_privileges
    log_info "Starting Prometheus installation..."

    # Get the server's IP address
    PROMETHEUS_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$PROMETHEUS_IP" ]; then
        PROMETHEUS_IP="localhost"
    fi

    # Download Prometheus
    PROMETHEUS_TAR="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    log_info "Downloading Prometheus ${PROMETHEUS_VERSION}..."
    wget "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_TAR}" -O "/tmp/${PROMETHEUS_TAR}"

    # Extract
    log_info "Extracting Prometheus..."
    tar -zxvf "/tmp/${PROMETHEUS_TAR}" -C /opt/
    sudo mv "/opt/prometheus-${PROMETHEUS_VERSION}.linux-amd64" /opt/prometheus

    # Clean up
    rm "/tmp/${PROMETHEUS_TAR}"

    # Create prometheus.yml configuration
    log_info "Configuring Prometheus to scrape Docker metrics..."
    cat <<EOF | sudo tee /opt/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["${PROMETHEUS_IP}:9090"]

  - job_name: "docker"
    static_configs:
      - targets: ["${DOCKER_MACHINE_IP}:9323"]
    metrics_path: /metrics
    scheme: http
EOF

    # Create Prometheus service
    log_info "Creating Prometheus systemd service..."
    cat <<EOF | sudo tee /etc/systemd/system/prometheus.service > /dev/null
[Unit]
Description=Prometheus service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/prometheus/prometheus --config.file=/opt/prometheus/prometheus.yml --storage.tsdb.path=/opt/prometheus/data --web.console.libraries=/opt/prometheus/console_libraries --web.console.templates=/opt/prometheus/consoles
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create data directory
    sudo mkdir -p /opt/prometheus/data
    sudo chown -R root:root /opt/prometheus

    # Reload systemd and start Prometheus
    log_info "Starting Prometheus service..."
    sudo systemctl daemon-reload
    sudo systemctl enable prometheus
    sudo systemctl start prometheus

    sleep 5
    sudo systemctl status prometheus --no-pager -n 3

    # Verify Prometheus is working
    log_info "Verifying Prometheus is accessible..."
    sleep 5
    if curl -s http://localhost:9090/-/ready > /dev/null; then
        log_info "✓ Prometheus is ready at http://${PROMETHEUS_IP}:9090"
    else
        log_warn "Prometheus may still be starting..."
    fi

    echo ""
    echo "=========================================="
    echo " Prometheus Machine Setup Complete!"
    echo "=========================================="
    echo ""
    echo "Prometheus version: $(/opt/prometheus/prometheus --version 2>/dev/null || echo "Unknown")"
    echo ""
    echo "Configuration:"
    echo "  - Prometheus UI: http://${PROMETHEUS_IP}:9090"
    echo "  - Scraping Docker metrics from: ${DOCKER_MACHINE_IP}:9323/metrics"
    echo "  - Grafana integration target: ${GRAFANA_IP}:3000"
    echo ""
    echo "Next steps:"
    echo "  1. Access Prometheus at: http://${PROMETHEUS_IP}:9090"
    echo "  2. On Grafana machine:"
    echo "     - Add Prometheus as data source: http://${PROMETHEUS_IP}:9090"
    echo "  3. Verify targets at: http://${PROMETHEUS_IP}:9090/targets"
    echo "=========================================="
}

# Main execution
check_privileges
install_prometheus