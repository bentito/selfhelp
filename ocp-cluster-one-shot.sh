#!/usr/bin/env bash
set -euo pipefail

# --- user-tunable settings (use OCP_* to avoid clashes with AWS_* cleanup) ---
OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-devcluster.openshift.com}"
OCP_REGION="${OCP_REGION:-us-east-1}"
OCP_ASSET_DIR="${OCP_ASSET_DIR:-/tmp/ocp1}"
OCP_CLUSTER_NAME="${OCP_CLUSTER_NAME:-btofel-netedg-$(date +%y%m%d)}"

# secrets/keys
PULL_SECRET_PATH="${PULL_SECRET_PATH:-/Users/btofel/.ocp-installer-pull-secret}"
SSH_PUBKEY_PATH="${SSH_PUBKEY_PATH:-/Users/btofel/.ssh/id_ed25519.pub}"

# aws environment bootstrapper
AWS_ENV_SCRIPT="${AWS_ENV_SCRIPT:-$HOME/bin/redhat-aws.sh}"

die() { echo "ERROR: $*" >&2; exit 1; }

# sanity checks
command -v openshift-install >/dev/null 2>&1 || die "openshift-install not found in PATH"
command -v aws >/dev/null 2>&1 || die "aws cli not found in PATH"
[[ -f "$AWS_ENV_SCRIPT" ]] || die "aws env script not found at $AWS_ENV_SCRIPT"
[[ -f "$PULL_SECRET_PATH" ]] || die "pull secret not found at $PULL_SECRET_PATH"
[[ -f "$SSH_PUBKEY_PATH" ]] || die "ssh public key not found at $SSH_PUBKEY_PATH"

# 1) source AWS profile setup (this will clear AWS_* env vars by design)
# shellcheck source=/dev/null
source "$AWS_ENV_SCRIPT"

echo "==> verifying aws profile in use"
aws configure list || die "failed to read aws configuration"
echo "==> identity check"
aws sts get-caller-identity || die "failed to get caller identity"

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

echo "==> launching openshift-install with dir=$OCP_ASSET_DIR"
openshift-install create cluster --dir "$OCP_ASSET_DIR" --log-level=info