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

# Versions (can be updated as needed)
GRAFANA_VERSION="11.1.4"
PROMETHEUS_VERSION="2.53.2"

echo "=========================================="
echo " Prometheus & Grafana Installation Script"
echo "=========================================="
log_warn "This script will install:"
log_warn "  - Grafana ${GRAFANA_VERSION} (port 3000)"
log_warn "  - Prometheus ${PROMETHEUS_VERSION} (port 9090)"
log_warn "  - Configure Docker metrics (port 9323)"
echo "------------------------------------------"
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
        return 0
    else
        log_error "This script requires sudo privileges"
        exit 1
    fi
}

# Step 1: Ensure Docker is installed and running
setup_docker() {
    log_info "Checking Docker installation..."

    if ! command -v docker &>/dev/null; then
        log_warn "Docker is not installed. Installing Docker..."

        # Remove old versions
        sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

        # Install prerequisites
        sudo apt-get update
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker CE
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        log_info "Docker installed successfully"
    else
        log_info "Docker is already installed"
    fi

    # Start and enable Docker
    log_info "Starting Docker service..."
    sudo systemctl enable docker
    sudo systemctl restart docker
    sudo systemctl status docker --no-pager -n 3

    # Configure Docker daemon to expose metrics on port 9323
    log_info "Configuring Docker daemon to expose metrics..."

    # Create or update daemon.json
    if [ ! -f "/etc/docker/daemon.json" ]; then
        sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "experimental": true,
  "metrics-addr": "0.0.0.0:9323",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
    else
        # Backup existing config
        sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
        # Update to add metrics if missing
        if ! grep -q "metrics-addr" /etc/docker/daemon.json; then
            sudo jq '. + {"metrics-addr": "0.0.0.0:9323", "experimental": true}' /etc/docker/daemon.json > /tmp/daemon.json && sudo mv /tmp/daemon.json /etc/docker/daemon.json
        fi
    fi

    sudo systemctl restart docker
    sleep 2
    log_info "Docker configured with metrics endpoint on port 9323"
}

# Step 2: Install Grafana
install_grafana() {
    log_info "Installing Grafana ${GRAFANA_VERSION}..."

    # Download Grafana
    GRAFANA_TAR="grafana-enterprise-${GRAFANA_VERSION}.linux-amd64.tar.gz"
    wget "https://dl.grafana.com/enterprise/release/${GRAFANA_TAR}" -O "/tmp/${GRAFANA_TAR}"

    # Extract
    tar -zxvf "/tmp/${GRAFANA_TAR}" -C /opt/
    sudo mv "/opt/grafana-${GRAFANA_VERSION}" /opt/grafana

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

    # Reload systemd and start Grafana
    sudo systemctl daemon-reload
    sudo systemctl enable grafana
    sudo systemctl start grafana

    sleep 3
    sudo systemctl status grafana --no-pager -n 3

    log_info "Grafana installed successfully on port 3000"
}

# Step 3: Install Prometheus
install_prometheus() {
    log_info "Installing Prometheus ${PROMETHEUS_VERSION}..."

    # Download Prometheus
    PROMETHEUS_TAR="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    wget "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_TAR}" -O "/tmp/${PROMETHEUS_TAR}"

    # Extract
    tar -zxvf "/tmp/${PROMETHEUS_TAR}" -C /opt/
    sudo mv "/opt/prometheus-${PROMETHEUS_VERSION}.linux-amd64" /opt/prometheus

    # Clean up
    rm "/tmp/${PROMETHEUS_TAR}"

    # Create prometheus.yml configuration
    log_info "Configuring Prometheus..."

    # Get the server's IP address
    SERVER_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="localhost"
    fi

    cat <<EOF | sudo tee /opt/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "docker"
    static_configs:
      - targets: ["localhost:9323"]
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
    sudo systemctl daemon-reload
    sudo systemctl enable prometheus
    sudo systemctl start prometheus

    sleep 3
    sudo systemctl status prometheus --no-pager -n 3

    log_info "Prometheus installed successfully on port 9090"
    log_info "Docker metrics are configured to be scraped from localhost:9323"
}

# Main execution
check_privileges

# Install all components in order
setup_docker
install_grafana
install_prometheus

echo ""
echo "=========================================="
echo " Installation Complete!"
echo "=========================================="
echo ""
echo "Services:"
echo "  - Grafana:    http://${SERVER_IP:-localhost}:3000"
echo "  - Prometheus: http://${SERVER_IP:-localhost}:9090"
echo ""
echo "Default Credentials:"
echo "  - Grafana: admin / admin (change on first login)"
echo ""
echo "Next Steps:"
echo "  1. Access Grafana at http://${SERVER_IP:-localhost}:3000"
echo "  2. Login with admin/admin"
echo "  3. Add Prometheus as data source:"
echo "     URL: http://${SERVER_IP:-localhost}:9090"
echo "  4. Import a dashboard or create your own"
echo ""
echo "To manage services:"
echo "  sudo systemctl {start,stop,restart,status} grafana"
echo "  sudo systemctl {start,stop,restart,status} prometheus"
echo ""
echo "Configuration files:"
echo "  Grafana: /opt/grafana/conf/defaults.ini"
echo "  Prometheus: /opt/prometheus/prometheus.yml"
echo "=========================================="
