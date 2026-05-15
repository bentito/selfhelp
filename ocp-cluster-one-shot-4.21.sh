#!/usr/bin/env bash
set -euo pipefail

# --- user-tunable settings (use OCP_* to avoid clashes with AWS_* cleanup) ---
OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-nids-dev.devcluster.openshift.com}"
OCP_REGION="${OCP_REGION:-us-west-2}"
OCP_ASSET_DIR="${OCP_ASSET_DIR:-$(pwd)/ocp-install-dir}"
OCP_CLUSTER_NAME="${OCP_CLUSTER_NAME:-${USER}-netedg-$(date +%y%m%d)}"

# secrets/keys
PULL_SECRET_PATH="${PULL_SECRET_PATH:-$HOME/.ocp-installer-pull-secret}"
SSH_PUBKEY_PATH="${SSH_PUBKEY_PATH:-$HOME/.ssh/id_ed25519.pub}"

# aws environment bootstrapper
AWS_ENV_SCRIPT="${AWS_ENV_SCRIPT:-$(dirname "$0")/redhat-aws.sh}"

die() { echo "ERROR: $*" >&2; exit 1; }

# sanity checks
command -v aws >/dev/null 2>&1 || die "aws cli not found in PATH"
[[ -f "$AWS_ENV_SCRIPT" ]] || die "aws env script not found at $AWS_ENV_SCRIPT"
[[ -f "$PULL_SECRET_PATH" ]] || die "pull secret not found at $PULL_SECRET_PATH"
[[ -f "$SSH_PUBKEY_PATH" ]] || die "ssh public key not found at $SSH_PUBKEY_PATH"

ensure_installer() {
    local VERSION="4.21.10"
    local BIN_NAME="openshift-install-4.21"
    local BIN_PATH="$HOME/bin/$BIN_NAME"
    
    if [[ -f "$BIN_PATH" ]]; then
        return 0
    fi

    echo "==> $BIN_NAME not found, attempting to download version $VERSION..."
    mkdir -p "$HOME/bin"
    
    local ARCH
    ARCH=$(uname -m)
    [[ "$ARCH" == "arm64" ]] || ARCH="x86_64"
    
    local OS="mac"
    [[ "$(uname)" == "Darwin" ]] || OS="linux"
    
    # Map architecture for the mirror URLs
    local MIRROR_ARCH="$ARCH"
    [[ "$ARCH" == "x86_64" ]] && MIRROR_ARCH="x86_64"
    [[ "$ARCH" == "arm64" ]] && MIRROR_ARCH="arm64"

    local URL="https://mirror.openshift.com/pub/openshift-v4/$MIRROR_ARCH/clients/ocp/$VERSION/openshift-install-$OS-$ARCH.tar.gz"
    if [[ "$OS" == "mac" && "$ARCH" == "x86_64" ]]; then
        URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$VERSION/openshift-install-mac.tar.gz"
    fi

    echo "    Downloading from $URL"
    curl -L -o "/tmp/$BIN_NAME.tar.gz" "$URL" || die "failed to download installer"
    tar -xzf "/tmp/$BIN_NAME.tar.gz" -C /tmp openshift-install || die "failed to extract installer"
    mv /tmp/openshift-install "$BIN_PATH"
    chmod +x "$BIN_PATH"
    echo "==> installed $BIN_NAME to $BIN_PATH"
}

ensure_installer

# 1) source AWS profile setup (this will clear AWS_* env vars by design)
# shellcheck source=/dev/null
source "$AWS_ENV_SCRIPT"

echo "==> verifying aws profile in use"
aws configure list || die "failed to read aws configuration"
echo "==> identity check"
aws sts get-caller-identity || die "failed to get caller identity"

# 1.5) AWS Networking Sanity Check (Idempotency fixes)
echo "==> performing aws networking sanity checks"

# A) VPC Block Public Access (Fixes the "horribly wrong" account-level block)
# This setting was likely changed during OCP 4.21 testing and blocks all IGW traffic.
BPA_MODE=$(aws ec2 describe-vpc-block-public-access-options --query 'VpcBlockPublicAccessOptions.InternetGatewayBlockMode' --output text 2>/dev/null || echo "off")
if [[ "$BPA_MODE" != "off" ]]; then
    echo "WARNING: VPC Block Public Access is set to '$BPA_MODE' in $OCP_REGION."
    echo "==> attempting to disable VPC Block Public Access (idempotent fix)..."
    aws ec2 modify-vpc-block-public-access-options --internet-gateway-block-mode off || echo "WARNING: failed to disable BPA (might lack permissions), install may fail."
else
    echo "OK: VPC Block Public Access is off."
fi

# B) Route53 Record Limit Check
# The account is currently at ~9500 records; the default limit is 10,000.
ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$OCP_BASE_DOMAIN" --query 'HostedZones[0].Id' --output text 2>/dev/null || echo "None")
if [[ "$ZONE_ID" != "None" && "$ZONE_ID" != "null" ]]; then
    RECORD_COUNT=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query 'length(ResourceRecordSets)' 2>/dev/null || echo "0")
    echo "INFO: Route53 records in $OCP_BASE_DOMAIN: $RECORD_COUNT"
    if (( RECORD_COUNT > 9800 )); then
        echo "CRITICAL WARNING: Route53 record count is at $RECORD_COUNT (Limit 10,000). Delete old clusters!"
    fi
else
    echo "WARNING: Could not find Route53 zone for $OCP_BASE_DOMAIN. DNS verification may fail."
fi

# 2) prep asset dir
rm -rf "$OCP_ASSET_DIR"
mkdir -p "$OCP_ASSET_DIR"

# 3) compose install-config.yaml
PULL_SECRET_CONTENT="$(cat "$PULL_SECRET_PATH")"
SSH_PUBKEY_CONTENT="$(cat "$SSH_PUBKEY_PATH")"

cat > "$OCP_ASSET_DIR/install-config.yaml" <<'YAML'
apiVersion: v1
baseDomain: __BASE_DOMAIN__
metadata:
  name: __CLUSTER_NAME__
platform:
  aws:
    region: __REGION__
credentialsMode: Manual
pullSecret: '__PULL_SECRET__'
sshKey: '__SSH_PUBKEY__'
YAML

# 4) safe placeholder substitution (handles quotes/newlines)
python3 - "$OCP_ASSET_DIR/install-config.yaml" <<PY
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
replacements = {
    "__BASE_DOMAIN__": """$OCP_BASE_DOMAIN""",
    "__CLUSTER_NAME__": """$OCP_CLUSTER_NAME""",
    "__REGION__": """$OCP_REGION""",
    "__PULL_SECRET__": """$PULL_SECRET_CONTENT""",
    "__SSH_PUBKEY__": """$SSH_PUBKEY_CONTENT""",
}
for k,v in replacements.items():
    s = s.replace(k, v)
p.write_text(s)
PY

# keep a backup (installer consumes install-config.yaml)
cp "$OCP_ASSET_DIR/install-config.yaml" "$OCP_ASSET_DIR/install-config.backup.yaml"

echo "==> creating manifests (phase 1) in $OCP_ASSET_DIR"
openshift-install-4.21 create manifests --dir "$OCP_ASSET_DIR" --log-level=info

echo "==> extracting CredentialsRequest manifests for ccoctl"
CRED_REQ_DIR="$OCP_ASSET_DIR/credrequests"
mkdir -p "$CRED_REQ_DIR"

# Extract CredentialsRequests using the oc CLI from the release payload
oc adm release extract \
    --credentials-requests \
    --cloud=aws \
    --to="$CRED_REQ_DIR" \
    quay.io/openshift-release-dev/ocp-release:4.21.10-x86_64 || die "failed to extract credrequests via oc adm"

# Check if we actually found any cred requests
if [ -z "$(ls -A "$CRED_REQ_DIR" 2>/dev/null)" ]; then
    echo "WARNING: No CredentialsRequest files found. This is unusual but we will try to proceed."
else
    echo "==> downloading ccoctl Linux binary for podman execution"
    CCOCTL_LINUX_DIR="$HOME/.ccoctl-linux-bin"
    mkdir -p "$CCOCTL_LINUX_DIR"
    
    if [[ ! -f "$CCOCTL_LINUX_DIR/ccoctl" ]]; then
        curl -s -L -o "/tmp/ccoctl-linux.tar.gz" "https://mirror.openshift.com/pub/openshift-v4/arm64/clients/ocp/4.21.10/ccoctl-linux-4.21.10.tar.gz" || die "failed to download linux ccoctl"
        tar -xzf "/tmp/ccoctl-linux.tar.gz" -C "$CCOCTL_LINUX_DIR" ccoctl || die "failed to extract linux ccoctl"
    fi

    echo "==> provisioning AWS IAM roles with ccoctl via podman"
    
    # We must pass the AWS credentials from our current SAML session into the podman container.
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile "$AWS_PROFILE")
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile "$AWS_PROFILE")
    AWS_SESSION_TOKEN=$(aws configure get aws_session_token --profile "$AWS_PROFILE")

    # Run the extracted Linux ccoctl binary inside a standard ubuntu container (glibc required)
    # We install ca-certificates first because ccoctl needs them to talk to AWS S3/IAM endpoints.
    podman run --rm \
        -v "$OCP_ASSET_DIR:/data:Z" \
        -v "$CCOCTL_LINUX_DIR:/bin-mount:Z" \
        -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        -e AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN" \
        -e AWS_REGION="$OCP_REGION" \
        docker.io/ubuntu:latest \
        bash -c "apt-get update -qq && apt-get install -y -qq ca-certificates && /bin-mount/ccoctl aws create-all --name=\"$OCP_CLUSTER_NAME\" --region=\"$OCP_REGION\" --credentials-requests-dir=\"/data/credrequests\" --output-dir=\"/data/ccoctl-output\"" || die "ccoctl provisioning failed via podman"

    echo "==> injecting ccoctl manifests into installer asset dir"
    cp -r "$OCP_ASSET_DIR/ccoctl-output/manifests/"* "$OCP_ASSET_DIR/manifests/" || die "failed to inject ccoctl manifests"
    cp -r "$OCP_ASSET_DIR/ccoctl-output/tls/"* "$OCP_ASSET_DIR/tls/" 2>/dev/null || true # Optional tls dir
fi

echo "==> launching openshift-install-4.21 create cluster (phase 2) with dir=$OCP_ASSET_DIR"
openshift-install-4.21 create cluster --dir "$OCP_ASSET_DIR" --log-level=info