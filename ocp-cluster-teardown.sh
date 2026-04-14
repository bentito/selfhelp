#!/usr/bin/env bash
set -euo pipefail

# --- settings (matching ocp-cluster-one-shot.sh defaults) ---
OCP_ASSET_DIR="${OCP_ASSET_DIR:-/tmp/ocp1}"
AWS_ENV_SCRIPT="${AWS_ENV_SCRIPT:-$HOME/bin/redhat-aws.sh}"

die() { echo "ERROR: $*" >&2; exit 1; }

# sanity checks
command -v openshift-install >/dev/null 2>&1 || die "openshift-install not found in PATH"
[[ -f "$AWS_ENV_SCRIPT" ]] || die "aws env script not found at $AWS_ENV_SCRIPT"

# 1) source AWS profile setup
# shellcheck source=/dev/null
source "$AWS_ENV_SCRIPT"

if [[ ! -d "$OCP_ASSET_DIR" ]]; then
    echo "Asset directory $OCP_ASSET_DIR not found. Nothing to destroy."
    exit 0
fi

if [[ ! -f "$OCP_ASSET_DIR/metadata.json" ]]; then
    echo "metadata.json not found in $OCP_ASSET_DIR. The installer needs this to identify resources."
    die "Cannot safely destroy cluster without metadata.json in $OCP_ASSET_DIR"
fi

echo "==> destroying cluster in $OCP_ASSET_DIR"
openshift-install destroy cluster --dir "$OCP_ASSET_DIR" --log-level=info

echo "==> cleanup asset dir"
rm -rf "$OCP_ASSET_DIR"
echo "Done."
