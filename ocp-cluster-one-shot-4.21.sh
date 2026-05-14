#!/usr/bin/env bash
set -euo pipefail

# --- user-tunable settings (use OCP_* to avoid clashes with AWS_* cleanup) ---
OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-nids-dev.devcluster.openshift.com}"
OCP_REGION="${OCP_REGION:-us-east-1}"
OCP_ASSET_DIR="${OCP_ASSET_DIR:-/tmp/ocp1}"
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

echo "==> launching openshift-install-4.21 with dir=$OCP_ASSET_DIR"
openshift-install-4.21 create cluster --dir "$OCP_ASSET_DIR" --log-level=info