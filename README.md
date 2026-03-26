# Devops Automation Scripts

This repository contains an automated installation script (`install_services.sh`) to deploy and manage standard Devops tools.

## How to run `install_services.sh`

1. Clone this repository to your server:
   ```bash
   git clone https://github.com/SuhasLingam/devops.git
   cd devops
   ```
2. Make the script executable:
   ```bash
   chmod +x *.sh
   ```
3. Run the installer:
   ```bash
   ./install_services.sh
   ```
4. An interactive menu will appear. Type the number corresponding to the tool you want to install and press `Enter`.

## Available Options

When you run the script, you will be presented with the following options:

1. **Jenkins** - Installs Jenkins and configures sudo permissions.
2. **Tomcat (Port 8085)** - Deploys Apache Tomcat and configures it to run on port 8085.
3. **SonarQube & PostgreSQL** - Runs the deployment script for SonarQube and its PostgreSQL database.
4. **Docker CE** - Installs Docker Community Edition.
5. **Ansible (Master/Node)** - Runs the automated setup for an Ansible Master or Node instance.
6. **Kubernetes - Master Node** - Sets up a Kubernetes Master Node.
7. **Kubernetes - Worker Node** - Sets up a Kubernetes Worker Node. ( only run this after master node is installed )
8. **Prometheus & Grafana (All-in-One)** - Installs Prometheus, Grafana, and Docker on the same machine.
9. **Docker Machine (Metrics Exporter)** - Installs Docker and configures it to expose metrics.
10. **Prometheus Machine** - Installs and configures a standalone Prometheus machine.
11. **Grafana Machine** - Installs and configures a standalone Grafana machine.
12. **Exit** - Exits the installation manager.

## Default Ports

After installation, the services will be running on the following default ports:

- **Jenkins**: 8080
- **Tomcat**: 8085 (Changed from 8080 to prevent conflicts)
- **SonarQube**: 9000
- **Grafana**: 3000
- **Prometheus**: 9090
- **Docker Metrics**: 9323 (Used for scraping by Prometheus)
- **Kubernetes API Server**: 6443
