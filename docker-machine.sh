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

# Configuration for Docker machine
DOCKER_LOGGING_DRIVER="json-file"
MAX_LOG_SIZE="100m"
MAX_LOG_FILES="3"
STORAGE_DRIVER="overlay2"

echo "=========================================="
echo " Docker Machine Setup (Metrics Exporter)"
echo "=========================================="
log_info "This machine will:"
log_info "  - Install Docker CE"
log_info "  - Expose metrics on port 9323 for Prometheus"
log_info "  - Configure for Prometheus scraping"
echo ""

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
        return 0
    else
        log_error "This script requires sudo privileges"
        exit 1
    fi
}

# Function: Install Docker CE
install_docker() {
    check_privileges
    log_info "Starting Docker CE installation..."

    # 1. Remove old versions (if any)
    log_info "Removing old Docker packages..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

    # 2. Install prerequisites
    log_info "Installing prerequisites..."
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    # 3. Add Docker's official GPG key
    log_info "Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # 4. Add Docker repository
    log_info "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 5. Install Docker CE
    log_info "Installing Docker packages..."
    sudo apt-get update
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # 6. Configure daemon.json for metrics exposure
    log_info "Configuring Docker daemon for Prometheus metrics..."

    # Create or update daemon.json
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "${DOCKER_LOGGING_DRIVER}",
  "log-opts": {
    "max-size": "${MAX_LOG_SIZE}",
    "max-file": "${MAX_LOG_FILES}"
  },
  "storage-driver": "${STORAGE_DRIVER}",
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "live-restore": true,
  "experimental": true,
  "metrics-addr": "0.0.0.0:9323"
}
EOF

    # 7. Start and enable Docker service
    log_info "Starting Docker service..."
    sudo systemctl daemon-reload
    sudo systemctl enable docker
    sudo systemctl restart docker
    sudo systemctl status docker --no-pager -n 3

    # 8. Add user to docker group (if not root)
    ACTUAL_USER="${SUDO_USER:-$(whoami)}"
    if [ "$ACTUAL_USER" != "root" ]; then
        log_info "Adding user '$ACTUAL_USER' to docker group..."
        sudo usermod -aG docker "$ACTUAL_USER"
        log_warn "User '$ACTUAL_USER' added to docker group. You may need to log out and back in for this to take effect."
    fi

    # 9. Verify installation
    log_info "Verifying Docker installation..."
    sudo docker --version
    sudo docker compose version

    # 10. Test metrics endpoint
    log_info "Testing Docker metrics endpoint..."
    sleep 5  # Give Docker time to start
    if curl -s http://localhost:9323/metrics | head -5 > /dev/null; then
        log_info "✓ Docker metrics endpoint is working on port 9323"
    else
        log_warn "Docker metrics endpoint test failed. Docker may still be starting..."
    fi

    echo ""
    echo "=========================================="
    echo " Docker Machine Setup Complete!"
    echo "=========================================="
    echo ""
    echo "Docker version: $(sudo docker --version)"
    echo "Docker Compose version: $(sudo docker compose version 2>/dev/null || echo 'Not available')"
    echo ""
    echo "Configuration:"
    echo "  - Docker metrics endpoint: http://<this-machine-ip>:9323/metrics"
    echo ""
    if [ "$ACTUAL_USER" != "root" ]; then
        echo "To use Docker without sudo:"
        echo "  1. Log out and log back in"
        echo "  2. Or run: newgrp docker"
        echo ""
    fi
    echo "Next steps:"
    echo "  1. Note this machine's IP address"
    echo "  2. On Prometheus machine, configure scrape target as:"
    echo "     <docker-machine-ip>:9323/metrics"
    echo "  3. Run prometheus-machine.sh on the Prometheus server"
    echo "  4. Run grafana-machine.sh on the Grafana server"
    echo "=========================================="
}

# Main execution
check_privileges
install_docker