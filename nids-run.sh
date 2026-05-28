#!/usr/bin/env bash
set -euo pipefail

# NIDS Container Wrapper
# This script runs the nids-dev container with all necessary mounts and environment variables.

IMAGE_NAME="nids-dev:latest"
HOST_UID=$(id -u)
KRB5_HOST_PATH="${HOME}/.krb5cc_nids"

# 1. Check for Podman VM clock drift (macOS/Windows)
if podman machine list 2>/dev/null | grep -qi "running"; then
    echo "==> Checking Podman VM clock synchronization..."
    HOST_TIME=$(date +%s)
    PODMAN_TIME=$(podman machine ssh date +%s 2>/dev/null || echo "$HOST_TIME")
    DIFF=$(( HOST_TIME - PODMAN_TIME ))
    DIFF=${DIFF#-} # absolute value
    if (( DIFF > 120 )); then
        echo "    [WARNING] Podman VM clock is out of sync by $DIFF seconds (likely due to sleep)."
        echo "    Restarting Podman machine to prevent AWS Signature errors..."
        podman machine stop
        podman machine start
    else
        echo "    Clock is synced (diff: ${DIFF}s)."
    fi
fi

# 2. Ensure the Podman image exists
if ! podman image exists "$IMAGE_NAME"; then
    echo "==> Container image $IMAGE_NAME not found. Building..."
    podman build -t "$IMAGE_NAME" -f "$(dirname "$0")/nids-dev.Containerfile" "$(dirname "$0")"
fi

# 2. Ensure Kerberos ticket is available in FILE format on host
# Macs and some Linux distros use non-file caches (API/KCM) by default.
# We must ensure a FILE-based cache exists for mounting into Podman.
KINIT_OPTS=""
# Optional: look for a password file in project root or home to skip prompt
PASSWD_FILE="${PWD}/.krb-passwd"
[[ ! -f "$PASSWD_FILE" ]] && PASSWD_FILE="${HOME}/.krb-passwd"

if [[ -f "$PASSWD_FILE" ]]; then
    echo "    Using Kerberos password file: $PASSWD_FILE"
    KINIT_OPTS="--password-file=$PASSWD_FILE"
fi

echo "==> Ensuring Kerberos ticket is available in $KRB5_HOST_PATH..."
if ! KRB5CCNAME="FILE:${KRB5_HOST_PATH}" klist -s 2>/dev/null; then
    echo "    Refreshing file-based ticket cache..."
    # We use -c explicitly to force writing to the file cache
    kinit -c "FILE:${KRB5_HOST_PATH}" $KINIT_OPTS "${KERBEROS_ID:-${USER}}@IPA.REDHAT.COM" || exit 1
fi

# 3. Run the container

podman run -it --rm \
    --name nids-dev-shell \
    -v "$(pwd):/workspace:Z" \
    -v "$HOME/.aws:/home/developer/.aws:Z" \
    -v "$HOME/.ssh:/home/developer/.ssh:ro" \
    -v "$HOME/.ocp-installer-pull-secret:/home/developer/.ocp-installer-pull-secret:ro" \
    -v "${KRB5_HOST_PATH}:/tmp/krb5cc_1000:ro" \
    -e NIDS_CONTAINER="true" \
    -e USER="${USER:-}" \
    -e AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}" \
    -e KERBEROS_ID="${KERBEROS_ID:-$USER}" \
    -e OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-}" \
    -e OCP_REGION="${OCP_REGION:-}" \
    "$IMAGE_NAME" "$@"
