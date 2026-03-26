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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Configuration
PROMETHEUS_VERSION="2.53.2"
GRAFANA_VERSION="11.1.4"
GRAFANA_ADMIN_PASS=""
DOCKER_MACHINE_IP=""

echo "=========================================="
echo " Prometheus & Grafana All-in-One Setup"
echo "=========================================="
log_info "This script will install on THIS machine:"
log_info "  - Prometheus ${PROMETHEUS_VERSION}  (port 9090)"
log_info "  - Grafana Enterprise ${GRAFANA_VERSION}  (port 3000)"
echo ""

# Optional: Docker machine IP for metrics scraping
read -p "Enter Docker/Node-Exporter machine IP to scrape metrics from (leave empty to skip): " DOCKER_MACHINE_IP

read -p "Set Grafana admin password (leave empty to use default 'admin'): " GRAFANA_ADMIN_PASS

# -------------------------------------------------------
# Privilege check
# -------------------------------------------------------
check_privileges() {
    if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
        return 0
    else
        log_error "This script requires sudo privileges."
        exit 1
    fi
}

# -------------------------------------------------------
# Install Prometheus
# -------------------------------------------------------
install_prometheus() {
    log_step "Installing Prometheus ${PROMETHEUS_VERSION}..."

    LOCAL_IP=$(hostname -I | awk '{print $1}')
    [ -z "$LOCAL_IP" ] && LOCAL_IP="localhost"

    PROMETHEUS_TAR="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    log_info "Downloading Prometheus..."
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_TAR}" \
         -O "/tmp/${PROMETHEUS_TAR}"

    log_info "Extracting Prometheus..."
    sudo tar -zxf "/tmp/${PROMETHEUS_TAR}" -C /opt/
    sudo mv "/opt/prometheus-${PROMETHEUS_VERSION}.linux-amd64" /opt/prometheus
    rm "/tmp/${PROMETHEUS_TAR}"

    # Build prometheus.yml
    log_info "Writing Prometheus configuration..."

    SCRAPE_BLOCK=""
    if [ -n "$DOCKER_MACHINE_IP" ]; then
        SCRAPE_BLOCK="
  - job_name: \"docker\"
    static_configs:
      - targets: [\"${DOCKER_MACHINE_IP}:9323\"]
    metrics_path: /metrics
    scheme: http"
    fi

    cat <<EOF | sudo tee /opt/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["${LOCAL_IP}:9090"]
${SCRAPE_BLOCK}
EOF

    sudo mkdir -p /opt/prometheus/data
    sudo chown -R root:root /opt/prometheus

    # Create systemd service
    log_info "Creating Prometheus systemd service..."
    cat <<EOF | sudo tee /etc/systemd/system/prometheus.service > /dev/null
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --web.console.libraries=/opt/prometheus/console_libraries \
  --web.console.templates=/opt/prometheus/consoles
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable prometheus
    sudo systemctl start prometheus

    sleep 5
    sudo systemctl status prometheus --no-pager -n 3

    if curl -s http://localhost:9090/-/ready > /dev/null 2>&1; then
        log_info "✓ Prometheus is ready at http://${LOCAL_IP}:9090"
    else
        log_warn "Prometheus may still be starting up. Check: sudo systemctl status prometheus"
    fi
}

# -------------------------------------------------------
# Install Grafana
# -------------------------------------------------------
install_grafana() {
    log_step "Installing Grafana Enterprise ${GRAFANA_VERSION}..."

    LOCAL_IP=$(hostname -I | awk '{print $1}')
    [ -z "$LOCAL_IP" ] && LOCAL_IP="localhost"

    GRAFANA_TAR="grafana-enterprise-${GRAFANA_VERSION}.linux-amd64.tar.gz"
    log_info "Downloading Grafana Enterprise..."
    wget -q "https://dl.grafana.com/enterprise/release/${GRAFANA_TAR}" \
         -O "/tmp/${GRAFANA_TAR}"

    log_info "Extracting Grafana..."
    sudo tar -zxf "/tmp/${GRAFANA_TAR}" -C /opt/

    EXTRACTED_DIR=$(find /opt -maxdepth 1 -type d -name "grafana*${GRAFANA_VERSION}*" | head -n 1)
    if [ -n "$EXTRACTED_DIR" ]; then
        sudo mv "$EXTRACTED_DIR" /opt/grafana
    else
        log_error "Could not find extracted Grafana directory."
        exit 1
    fi
    rm "/tmp/${GRAFANA_TAR}"

    sudo mkdir -p /var/lib/grafana
    sudo chown -R root:root /var/lib/grafana

    # Create systemd service
    log_info "Creating Grafana systemd service..."
    cat <<EOF | sudo tee /etc/systemd/system/grafana.service > /dev/null
[Unit]
Description=Grafana Dashboard
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/grafana/bin/grafana-server \
  --config=/opt/grafana/conf/defaults.ini \
  --homepath=/opt/grafana \
  --packaging=deb
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable grafana
    sudo systemctl start grafana

    sleep 5
    sudo systemctl status grafana --no-pager -n 3

    # Auto-configure Prometheus data source via Grafana API
    log_info "Waiting for Grafana to be ready..."
    for i in $(seq 1 12); do
        if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
            log_info "✓ Grafana is up."
            break
        fi
        sleep 5
    done

    GRAFANA_PASS="${GRAFANA_ADMIN_PASS:-admin}"

    log_info "Configuring Prometheus as Grafana data source..."
    DS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST http://localhost:3000/api/datasources \
        -H "Content-Type: application/json" \
        -u "admin:admin" \
        -d "{
            \"name\": \"Prometheus\",
            \"type\": \"prometheus\",
            \"url\": \"http://localhost:9090\",
            \"access\": \"proxy\",
            \"isDefault\": true
        }")

    if [ "$DS_RESPONSE" = "200" ] || [ "$DS_RESPONSE" = "409" ]; then
        log_info "✓ Prometheus data source configured in Grafana."
    else
        log_warn "Data source auto-configuration returned HTTP ${DS_RESPONSE}. Configure manually if needed."
    fi

    # Change admin password if provided
    if [ -n "$GRAFANA_ADMIN_PASS" ]; then
        log_info "Updating Grafana admin password..."
        curl -s -X PUT http://localhost:3000/api/user/password \
            -H "Content-Type: application/json" \
            -u "admin:admin" \
            -d "{\"oldPassword\":\"admin\",\"newPassword\":\"${GRAFANA_ADMIN_PASS}\",\"confirmNew\":\"${GRAFANA_ADMIN_PASS}\"}" \
            > /dev/null && log_info "✓ Admin password updated." || log_warn "Could not auto-update password. Change it on first login."
    fi
}

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
print_summary() {
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    [ -z "$LOCAL_IP" ] && LOCAL_IP="<this-machine-ip>"

    echo ""
    echo "=========================================="
    echo " Prometheus & Grafana Setup Complete!"
    echo "=========================================="
    echo ""
    echo "  Prometheus UI : http://${LOCAL_IP}:9090"
    echo "  Grafana UI    : http://${LOCAL_IP}:3000"
    echo ""
    echo "  Grafana credentials:"
    echo "    Username : admin"
    if [ -n "$GRAFANA_ADMIN_PASS" ]; then
        echo "    Password : [your custom password]"
    else
        echo "    Password : admin  ← CHANGE ON FIRST LOGIN"
    fi
    if [ -n "$DOCKER_MACHINE_IP" ]; then
        echo ""
        echo "  Scraping metrics from : ${DOCKER_MACHINE_IP}:9323"
    fi
    echo ""
    echo "  Next steps:"
    echo "    1. Open Grafana: http://${LOCAL_IP}:3000"
    echo "    2. Prometheus data source is pre-configured."
    echo "    3. Import a dashboard (e.g., Docker monitoring ID: 6417)"
    echo "    4. Check Prometheus targets: http://${LOCAL_IP}:9090/targets"
    echo "=========================================="
}

# -------------------------------------------------------
# Main
# -------------------------------------------------------
check_privileges
install_prometheus
install_grafana
print_summary
