#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking prerequisites for NIDS AWS Deployment..."

# 1. Check VPN/Network (Can we reach internal GitLab?)
if ! curl -I -s --connect-timeout 5 https://gitlab.cee.redhat.com >/dev/null; then
    echo "WARNING: Cannot reach gitlab.cee.redhat.com."
    echo "         Please ensure you are connected to the Red Hat GlobalProtect VPN."
    echo "         The installation of internal tools will likely fail."
    echo ""
fi

# 2. Check System Dependencies (kinit)
if ! command -v kinit >/dev/null 2>&1; then
    echo "WARNING: 'kinit' not found on your system."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "         Mac Users: You may need to run: brew install krb5"
    else
        echo "         Linux Users: You may need to run: sudo dnf install krb5-devel python3-devel openldap-devel"
    fi
    echo ""
fi

# 3. Check Required Files
if [[ ! -f "$HOME/.ocp-installer-pull-secret" ]]; then
    echo "WARNING: Missing OpenShift Pull Secret at $HOME/.ocp-installer-pull-secret"
    echo "         Download it from: https://console.redhat.com/openshift/install/pull-secret"
    echo ""
fi

if [[ ! -f "$HOME/.ssh/id_ed25519.pub" && ! -f "$HOME/.ssh/id_rsa.pub" ]]; then
    echo "WARNING: No default SSH public key found in $HOME/.ssh/"
    echo "         You may need to run: ssh-keygen -t ed25519"
    echo ""
fi

# 4. Build Podman Image
IMAGE_NAME="nids-dev:latest"
echo "==> Building Podman image $IMAGE_NAME..."
echo "    (Note: This is also handled automatically by the one-shot scripts)"
if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: 'podman' not found. Please install Podman first."
    exit 1
fi

podman build --platform "linux/$(podman info --format '{{.Host.Arch}}')" -t "$IMAGE_NAME" -f nids-dev.Containerfile .

echo "------------------------------------------------------------"
echo "==> Setup Complete!"
echo "The NIDS development environment is containerized."
echo ""
echo "You can now run any deployment script directly from your host:"
echo "    ./ocp-cluster-one-shot-4.21.sh"
echo ""
echo "Everything (Kerberos, Image Build, AWS SAML) is handled automatically."
echo "------------------------------------------------------------"
