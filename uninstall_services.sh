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

# CAUTION: This script will completely remove Jenkins, Tomcat, SonarQube, and PostgreSQL

echo "=========================================="
echo " Service Uninstallation Script"
echo "=========================================="
log_warn "WARNING: This will delete ALL services and data!"
read -p "Are you absolutely sure you want to continue? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    log_info "Uninstallation cancelled."
    exit 1
fi

log_info "1. Stopping and Removing SonarQube..."
sudo systemctl stop sonar || true
sudo systemctl disable sonar || true
sudo rm -f /etc/systemd/system/sonar.service
sudo systemctl daemon-reload
sudo rm -rf /opt/sonarqube
sudo userdel ddsonar || true
sudo groupdel ddsonar || true

log_info "2. Stopping and Removing Jenkins..."
sudo systemctl stop jenkins || true
sudo systemctl disable jenkins || true
sudo apt-get remove --purge jenkins -y
sudo rm -rf /var/lib/jenkins
sudo rm -rf /var/cache/jenkins
sudo rm -f /etc/default/jenkins

log_info "3. Removing Tomcat..."
# Try to find the tomcat directory in common places
TOMCAT_DIR=$(find /home /opt -maxdepth 2 -name "apache-tomcat-*" -type d 2>/dev/null | head -n 1)
if [ -n "$TOMCAT_DIR" ]; then
    echo "Found Tomcat at $TOMCAT_DIR. Removing..."
    # Check if running
    pgrep -f "tomcat" | xargs -r sudo kill -9
    sudo rm -rf "$TOMCAT_DIR"
else
    echo "Tomcat directory not found, skipping..."
fi

log_info "4. Removing PostgreSQL..."
sudo systemctl stop postgresql || true
sudo apt-get remove --purge postgresql postgresql-contrib postgresql-common -y
sudo rm -rf /etc/postgresql/
sudo rm -rf /etc/postgresql-common/
sudo rm -rf /var/lib/postgresql/
sudo userdel -r postgres || true
sudo groupdel postgres || true

log_info "5. Removing Ansible and devops user..."
sudo apt-get remove --purge ansible -y
sudo apt-add-repository --remove ppa:ansible/ansible -y
sudo userdel -r devops || true
sudo groupdel devops || true
sudo rm -f /etc/sudoers.d/devops

log_info "6. Removing Prometheus and Grafana..."
sudo systemctl stop prometheus || true
sudo systemctl disable prometheus || true
sudo rm -f /etc/systemd/system/prometheus.service
sudo rm -rf /opt/prometheus

sudo systemctl stop grafana || true
sudo systemctl disable grafana || true
sudo rm -f /etc/systemd/system/grafana.service
sudo rm -rf /opt/grafana
sudo rm -rf /var/lib/grafana

log_info "7. Cleaning up Dependencies (Java, Unzip, etc.)..."
sudo apt-get autoremove -y
sudo apt-get autoclean

echo "=========================================="
log_info " Cleanup Complete!"
log_info " All services, Ansible, Prometheus, Grafana, and related data have been removed."
echo "=========================================="
