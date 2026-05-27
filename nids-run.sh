#!/usr/bin/env bash
set -euo pipefail

# NIDS Container Wrapper
# This script runs the nids-dev container with all necessary mounts and environment variables.

IMAGE_NAME="nids-dev:latest"
HOST_UID=$(id -u)
KRB5_HOST_PATH="/tmp/krb5cc_${HOST_UID}"

# 1. Ensure the Podman image exists
if ! podman image exists "$IMAGE_NAME"; then
    echo "==> Container image $IMAGE_NAME not found. Building..."
    podman build -t "$IMAGE_NAME" -f "$(dirname "$0")/nids-dev.Containerfile" "$(dirname "$0")"
fi

# 2. Ensure Kerberos ticket is available on host
if ! klist -s 2>/dev/null; then
    echo "==> No active Kerberos ticket found. Please authenticate:"
    kinit "${KERBEROS_ID:-${USER}}@IPA.REDHAT.COM"
fi

# Many modern systems use KCM or API based ticket caches. 
# We need to export it to a file for mounting into Podman.
echo "==> Exporting Kerberos ticket to $KRB5_HOST_PATH for container use..."
# Force export to file cache if it doesn't match the standard path or if we need to refresh
KRB5CCNAME="FILE:${KRB5_HOST_PATH}" kinit -R 2>/dev/null || KRB5CCNAME="FILE:${KRB5_HOST_PATH}" kinit "${KERBEROS_ID:-${USER}}@IPA.REDHAT.COM"

# 3. Run the container
podman run -it --rm \
    --name nids-dev-shell \
    -v "$(pwd):/workspace:Z" \
    -v "$HOME/.aws:/home/developer/.aws:Z" \
    -v "$HOME/.ssh:/home/developer/.ssh:ro" \
    -v "$HOME/.ocp-installer-pull-secret:/home/developer/.ocp-installer-pull-secret:ro" \
    -v "${KRB5_HOST_PATH}:/tmp/krb5cc_1000:ro" \
    -e NIDS_CONTAINER="true" \
    -e AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}" \
    -e KERBEROS_ID="${KERBEROS_ID:-$USER}" \
    -e OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-}" \
    -e OCP_REGION="${OCP_REGION:-}" \
    "$IMAGE_NAME" "$@"
