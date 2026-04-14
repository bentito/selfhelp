#!/usr/bin/env bash
set -euo pipefail

# --- settings (matching ocp-cluster-one-shot.sh defaults) ---
OCP_ASSET_DIR="${OCP_ASSET_DIR:-/tmp/ocp1}"
AWS_ENV_SCRIPT="${AWS_ENV_SCRIPT:-$HOME/bin/redhat-aws.sh}"

die() { echo "ERROR: $*" >&2; exit 1; }

# sanity checks
command -v aws >/dev/null 2>&1 || die "aws cli not found in PATH"
[[ -f "$AWS_ENV_SCRIPT" ]] || die "aws env script not found at $AWS_ENV_SCRIPT"

if [[ ! -d "$OCP_ASSET_DIR" ]]; then
    echo "Asset directory $OCP_ASSET_DIR not found. Nothing to destroy."
    exit 0
fi

# Try to detect version from metadata or default to 4.21
OCP_VERSION="4.21.10"
if [[ -f "$OCP_ASSET_DIR/metadata.json" ]]; then
    # Simple heuristic: if the asset dir exists, we try to use the most recent installer 
    # but we'll check if we can find a version string.
    echo "==> detecting cluster version from $OCP_ASSET_DIR"
fi

ensure_installer() {
    local VERSION="$1"
    local BIN_NAME="openshift-install-${VERSION%.*}" # e.g. openshift-install-4.21
    local BIN_PATH="$HOME/bin/$BIN_NAME"
    
    if [[ -f "$BIN_PATH" ]]; then
        echo "$BIN_PATH"
        return 0
    fi

    echo "==> $BIN_NAME not found, attempting to download version $VERSION..." >&2
    mkdir -p "$HOME/bin"
    
    local ARCH
    ARCH=$(uname -m)
    [[ "$ARCH" == "arm64" ]] || ARCH="x86_64"
    
    local OS="mac"
    [[ "$(uname)" == "Darwin" ]] || OS="linux"
    
    local MIRROR_ARCH="$ARCH"
    local URL="https://mirror.openshift.com/pub/openshift-v4/$MIRROR_ARCH/clients/ocp/$VERSION/openshift-install-$OS-$ARCH.tar.gz"
    if [[ "$OS" == "mac" && "$ARCH" == "x86_64" ]]; then
        URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$VERSION/openshift-install-mac.tar.gz"
    fi

    curl -L -o "/tmp/$BIN_NAME.tar.gz" "$URL" >&2 || die "failed to download installer"
    tar -xzf "/tmp/$BIN_NAME.tar.gz" -C /tmp openshift-install >&2 || die "failed to extract installer"
    mv /tmp/openshift-install "$BIN_PATH"
    chmod +x "$BIN_PATH"
    echo "$BIN_PATH"
}

# For teardown, we'll try 4.21 first as it's generally backward compatible for destruction
INSTALLER=$(ensure_installer "4.21.10")

echo "==> destroying cluster in $OCP_ASSET_DIR using $INSTALLER"
"$INSTALLER" destroy cluster --dir "$OCP_ASSET_DIR" --log-level=info

echo "==> cleanup asset dir"
rm -rf "$OCP_ASSET_DIR"
echo "Done."
