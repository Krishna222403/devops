#!/bin/bash

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

# Define the services
SERVICES=("jenkins" "tomcat" "sonar" "postgresql" "grafana" "prometheus" "ssh")

echo "=========================================="
echo " Service Management Script"
echo "=========================================="
echo "Available: Jenkins, Tomcat, SonarQube, PostgreSQL, Grafana, Prometheus, SSH, Ansible"
echo "------------------------------------------"
echo "Options:"
echo "1) Stop all services"
echo "2) Start all services"
echo "3) Start a specific service"
echo "4) Check status of all services"
echo "5) Exit"
echo "=========================================="

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        log_info "Stopping all services..."
        for service in "${SERVICES[@]}"; do
            # Tomcat doesn't use a standard systemd service in your current setup, it uses startup.sh/shutdown.sh
            if [ "$service" == "tomcat" ]; then
                if [ -f "/opt/apache-tomcat-9.0.115/bin/shutdown.sh" ]; then
                    log_info "Stopping Tomcat..."
                    sudo /opt/apache-tomcat-9.0.115/bin/shutdown.sh
                elif [ -f "$(pwd)/apache-tomcat-9.0.115/bin/shutdown.sh" ]; then
                    log_info "Stopping Tomcat..."
                    sudo $(pwd)/apache-tomcat-9.0.115/bin/shutdown.sh
                else
                    log_warn "Tomcat shutdown script not found."
                fi
            else
                log_info "Stopping $service..."
                sudo systemctl stop $service || log_error "Failed to stop $service (might not be installed or running)"
            fi
        done
        log_info "All target services stopped."
        ;;
    2)
        log_info "Starting all services..."
        for service in "${SERVICES[@]}"; do
            if [ "$service" == "tomcat" ]; then
                if [ -f "/opt/apache-tomcat-9.0.115/bin/startup.sh" ]; then
                    log_info "Starting Tomcat..."
                    sudo /opt/apache-tomcat-9.0.115/bin/startup.sh
                elif [ -f "$(pwd)/apache-tomcat-9.0.115/bin/startup.sh" ]; then
                    log_info "Starting Tomcat..."
                    sudo $(pwd)/apache-tomcat-9.0.115/bin/startup.sh
                else
                    log_warn "Tomcat startup script not found."
                fi
            else
                log_info "Starting $service..."
                sudo systemctl start $service
                sudo systemctl status $service --no-pager
            fi
        done
        log_info "All target services started."
        ;;
    3)
        read -p "Enter the name of the service to start (jenkins, tomcat, sonar, postgresql, grafana, prometheus, ssh): " start_service
        # Convert to lowercase
        start_service=$(echo "$start_service" | tr '[:upper:]' '[:lower:]')

        if [ "$start_service" == "tomcat" ]; then
            if [ -f "/opt/apache-tomcat-9.0.115/bin/startup.sh" ]; then
                log_info "Starting Tomcat..."
                sudo /opt/apache-tomcat-9.0.115/bin/startup.sh
            elif [ -f "$(pwd)/apache-tomcat-9.0.115/bin/startup.sh" ]; then
                log_info "Starting Tomcat..."
                sudo $(pwd)/apache-tomcat-9.0.115/bin/startup.sh
            else
                log_warn "Tomcat startup script not found."
            fi
        elif [[ " ${SERVICES[@]} " =~ " ${start_service} " ]]; then
            log_info "Starting $start_service..."
            sudo systemctl start $start_service
            sudo systemctl status $start_service --no-pager
        else
            log_error "Invalid service name. Allowed values: jenkins, tomcat, sonar, postgresql, ssh"
        fi
        ;;
    4)
        log_info "Checking status of all services..."
        echo "------------------------------------------"
        for service in "${SERVICES[@]}"; do
            if [ "$service" == "tomcat" ]; then
               # Basic check to see if Java is running a Tomcat process
               if pgrep -f "tomcat" > /dev/null; then
                   echo "tomcat: active (running)"
               else
                   echo "tomcat: inactive (dead)"
               fi
            else
               status=$(systemctl is-active $service 2>/dev/null || echo "not installed")
               echo "$service: $status"
            fi
        done
        # Check Ansible specifically
        if command -v ansible &>/dev/null; then
            echo "ansible: installed ($(ansible --version | head -n 1))"
        else
            echo "ansible: not installed"
        fi
        ;;
    5)
        log_info "Exiting..."
        exit 0
        ;;
    *)
        log_error "Invalid choice. Exiting..."
        exit 1
        ;;
esac
