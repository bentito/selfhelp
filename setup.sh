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

# 4. Setup Python Virtual Environment
VENV_PATH="$(dirname "$0")/.aws-saml-venv"

if [[ ! -d "$VENV_PATH" ]]; then
    echo "==> Creating Python virtual environment in $VENV_PATH..."
    python3 -m venv "$VENV_PATH"
else
    echo "==> Virtual environment already exists at $VENV_PATH."
fi

# 5. Install aws-automation (SAML CLI tool)
echo "==> Activating virtual environment and installing Red Hat aws-automation tools..."
source "$VENV_PATH/bin/activate"

pip install --upgrade pip

# Note: GIT_SSL_NO_VERIFY is required for some RH environments where self-signed certs
# are used on the internal GitLab instance.
GIT_SSL_NO_VERIFY=true pip install --upgrade git+https://gitlab.cee.redhat.com/compute/aws-automation.git

echo "------------------------------------------------------------"
echo "==> Setup Complete!"
echo "You are ready to deploy. If your local system username does not match"
echo "your Red Hat Kerberos ID, please export it before running the scripts:"
echo "    export KERBEROS_ID=johndoe"
echo ""
echo "To launch a cluster, run:"
echo "    ./ocp-cluster-one-shot-4.21.sh"
echo "------------------------------------------------------------"
