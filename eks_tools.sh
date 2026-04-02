#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "================================================="
echo " EKS Necessary Tools Installation"
echo "================================================="

# 1. Update system and install basic tools
log_info "Installing basic dependencies (curl, unzip, git)..."
sudo apt-get update -y || sudo yum update -y
sudo apt-get install -y curl unzip git || sudo yum install -y curl unzip git

# 2. Install AWS CLI v2
if ! command -v aws &> /dev/null; then
    log_info "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
else
    log_info "AWS CLI is already installed."
fi

# 3. Install kubectl
if ! command -v kubectl &> /dev/null; then
    log_info "Installing kubectl..."
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.24.11/2023-03-17/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
else
    log_info "kubectl is already installed."
fi

# 4. Install eksctl
if ! command -v eksctl &> /dev/null; then
    log_info "Installing eksctl..."
    curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
else
    log_info "eksctl is already installed."
fi

echo ""
echo "================================================="
echo " TOOLS INSTALLED SUCCESSFULLY"
echo "================================================="
