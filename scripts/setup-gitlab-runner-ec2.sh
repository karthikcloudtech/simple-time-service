#!/bin/bash

###############################################################################
# GitLab Runner Setup Script for AWS EC2 (Amazon Linux 2023)
# Run this script on your EC2 instance to set up GitLab Runner
###############################################################################

set -euo pipefail

echo "=========================================="
echo "GitLab Runner Setup for AWS EC2 (AL2023)"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS"
    exit 1
fi

echo "Detected OS: $OS"

# Update system
echo "Updating system packages..."
if [ "$OS" = "amzn" ]; then
    dnf update -y
else
    echo "Unsupported OS. This script supports Amazon Linux 2023"
    exit 1
fi

# Install Docker (required for Docker executor)
echo "Installing Docker..."
dnf install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user  # Add ec2-user to docker group (AL2023 default user)

# Install GitLab Runner
echo "Installing GitLab Runner..."
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | bash
dnf install -y gitlab-runner

# Install required tools (for terraform jobs that need AWS CLI, kubectl, helm)
echo "Installing additional tools..."
dnf install -y curl wget jq unzip git
dnf install -y python3 python3-pip

# Check and install/upgrade AWS CLI (AL2023 comes with AWS CLI v1, v2 is recommended)
if command -v aws &> /dev/null; then
    echo "AWS CLI already installed: $(aws --version)"
    echo "Upgrading to AWS CLI v2 (recommended)..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    rm -rf /tmp/awscliv2.zip /tmp/aws
    echo "AWS CLI upgraded: $(aws --version)"
else
    echo "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
    rm -rf /tmp/awscliv2.zip /tmp/aws
    echo "AWS CLI installed: $(aws --version)"
fi

# Install kubectl
echo "Installing kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl

# Install helm
echo "Installing helm..."
HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name' || echo "v3.15.0")
curl -LO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
tar -zxvf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
mv linux-amd64/helm /usr/local/bin/helm
rm -rf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64

# Install Terraform
echo "Installing Terraform..."
dnf install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y terraform

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Installed versions:"
echo "  Docker: $(docker --version)"
echo "  GitLab Runner: $(gitlab-runner --version | head -1)"
echo "  AWS CLI: $(aws --version)"
echo "  kubectl: $(kubectl version --client --short)"
echo "  helm: $(helm version --client --short)"
echo "  Terraform: $(terraform --version | head -1)"
echo ""
echo "Next steps:"
echo ""
echo "METHOD 1: Using GitLab Web UI (Recommended for GitLab Runner 15.6+):"
echo "1. Go to: Project → Settings → CI/CD → Runners → New instance runner"
echo "2. Fill in:"
echo "   - Description: simple-time-service-ec2-runner"
echo "   - Tags: project-specific"
echo "   - Run untagged jobs: No"
echo "3. Click 'Create runner'"
echo "4. Copy the authentication token shown on the page"
echo "5. Register the runner with the token:"
echo "   sudo gitlab-runner register --url https://gitlab.com/ --token <authentication-token> \\"
echo "     --executor docker --docker-image docker:latest --tag-list project-specific"
echo ""
echo "METHOD 2: Using Registration Token (Legacy - may not work on Runner 15.6+):"
echo "1. Get registration token from: Project → Settings → CI/CD → Runners"
echo "2. Register: sudo gitlab-runner register"
echo "   - URL: https://gitlab.com/"
echo "   - Token: <registration token>"
echo "   - Description: simple-time-service-ec2-runner"
echo "   - Tags: project-specific"
echo "   - Executor: docker"
echo "   - Default Docker image: docker:latest"
echo ""
echo "After registration:"
echo "1. Install GitLab Runner as a service and start:"
echo "   sudo gitlab-runner install"
echo "   sudo gitlab-runner start"
echo ""
echo "2. Verify it's running:"
echo "   sudo gitlab-runner status"
echo ""
echo "3. Check runner in GitLab UI:"
echo "   Project → Settings → CI/CD → Runners"
echo "   Should see runner online with tag 'project-specific'"
echo ""
echo "=========================================="

