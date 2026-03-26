#!/bin/bash
set -e # Exit immediately if a command fails

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

echo "=========================================="
echo " Service Installation Manager"
echo "=========================================="
echo "Which service would you like to install?"
echo "------------------------------------------"
echo "1) Jenkins"
echo "2) Tomcat (Port 8085)"
echo "3) SonarQube & PostgreSQL"
echo "4) Docker CE"
echo "5) Ansible (Master/Node)"
echo "6) Kubernetes - Master Node"
echo "7) Kubernetes - Worker Node"
echo "8) Prometheus & Grafana"
echo "9) Exit"
echo "=========================================="
read -p "Enter your choice (1-9): " choice

case $choice in
    1)
        log_info "Starting Jenkins deployment..."
        wget -q https://raw.githubusercontent.com/akshu20791/Deployment-script/refs/heads/main/jenkins.sh -O jenkins.sh
        chmod +x jenkins.sh
        sudo ./jenkins.sh

        # Automate the sudoers configuration (no manual visudo needed!)
        echo "jenkins ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/jenkins > /dev/null
        sudo chmod 440 /etc/sudoers.d/jenkins

        sudo systemctl restart jenkins
        log_info "Jenkins installed and sudoers configured successfully!"
        ;;
    2)
        log_info "Starting Tomcat deployment..."
        sudo apt update
        sudo apt install unzip -y

        # Download and extract Tomcat
        wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.115/bin/apache-tomcat-9.0.115.zip
        unzip -q apache-tomcat-9.0.115.zip

        # Clean up the zip file to save space
        rm apache-tomcat-9.0.115.zip

        # Navigate to Tomcat config and change port to 8085 to avoid Jenkins conflict
        cd apache-tomcat-9.0.115/conf/
        sed -i 's/port="8080"/port="8085"/g' server.xml

        # Make scripts executable and start Tomcat
        cd ../bin
        sudo chmod +x *.sh
        ./startup.sh

        log_info "Tomcat deployed successfully on port 8085!"
        ;;
    3)
        log_info "Starting SonarQube & PostgreSQL deployment..."
        if [ -f "./sonarqube.sh" ]; then
            chmod +x ./sonarqube.sh
            ./sonarqube.sh
            log_info "SonarQube deployment script executed successfully!"
        else
            log_error "sonarqube.sh script not found in the current directory."
            log_error "Please make sure sonarqube.sh is downloaded and available."
            exit 1
        fi
        ;;
    4)
        log_info "Starting Docker installation..."
        if [ -f "./docker_install.sh" ]; then
            chmod +x ./docker_install.sh
            ./docker_install.sh
        else
            log_error "docker_install.sh script not found in the current directory."
            exit 1
        fi
        ;;
    5)
        log_info "Starting Ansible deployment..."
        if [ -f "./ansible_setup.sh" ]; then
            chmod +x ./ansible_setup.sh
            ./ansible_setup.sh
        else
            log_error "ansible_setup.sh script not found in the current directory."
            exit 1
        fi
        ;;
    6)
        log_info "Starting Kubernetes Master setup..."
        if [ -f "./k8s_master.sh" ]; then
            chmod +x ./k8s_master.sh
            ./k8s_master.sh
        else
            log_error "k8s_master.sh script not found in the current directory."
            exit 1
        fi
        ;;
    7)
        log_info "Starting Kubernetes Worker Node setup..."
        if [ -f "./k8s_node.sh" ]; then
            chmod +x ./k8s_node.sh
            ./k8s_node.sh
        else
            log_error "k8s_node.sh script not found in the current directory."
            exit 1
        fi
        ;;
    8)
        log_info "Starting Prometheus & Grafana deployment..."
        if [ -f "./prometheus_grafana.sh" ]; then
            chmod +x ./prometheus_grafana.sh
            ./prometheus_grafana.sh
        else
            log_error "prometheus_grafana.sh script not found in the current directory."
            exit 1
        fi
        ;;
    9)
        log_info "Exiting..."
        exit 0
        ;;
    *)
        log_error "Invalid choice. Exiting..."
        exit 1
        ;;
esac
