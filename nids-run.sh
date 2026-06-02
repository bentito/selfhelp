#!/usr/bin/env bash
set -euo pipefail

# NIDS Container Wrapper
# This script runs the nids-dev container with all necessary mounts and environment variables.

IMAGE_NAME="nids-dev:latest"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
HOST_UID=$(id -u)
KRB5_HOST_PATH="${HOME}/.krb5cc_nids"

# 1. Ensure Container VM is running and clock is synced (macOS/Windows)
# This is currently Podman-specific.
if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    if podman machine list 2>/dev/null | grep -qE 'applehv|qemu|wsl|hyperv'; then
        echo "==> Ensuring Podman VM is running and clock is synced..."
        podman machine start 2>/dev/null || true
        
        HOST_TIME=$(date +%s)
        # Use a shorter timeout and handle potential SSH failures
        PODMAN_TIME=$(podman machine ssh date +%s 2>/dev/null || echo "0")
        
        # If PODMAN_TIME is 0, either the machine is still starting or SSH failed.
        # We skip sync in that case to avoid setting time to 1970.
        if [[ "$PODMAN_TIME" -gt 0 ]]; then
            DIFF=$(( HOST_TIME - PODMAN_TIME ))
            DIFF=${DIFF#-} # absolute value
            if (( DIFF > 5 )); then
                echo "    Syncing Podman VM clock (drift: ${DIFF}s)..."
                podman machine ssh sudo date -s "@$HOST_TIME" >/dev/null 2>&1 || true
            fi
        fi
    fi
fi

# 2. Ensure the container image exists
# We use both 'image exists' (podman) and 'inspect' (docker/podman) for compatibility
if ! "$CONTAINER_ENGINE" inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "==> Container image $IMAGE_NAME not found. Building..."
    "$CONTAINER_ENGINE" build -t "$IMAGE_NAME" -f "$(dirname "$0")/nids-dev.Containerfile" "$(dirname "$0")"
fi

# 3. Ensure Kerberos ticket is available in FILE format on host
# Macs and some Linux distros use non-file caches (API/KCM) by default.
# We must ensure a FILE-based cache exists for mounting into the container.
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

# 4. Run the container

# Linux-specific fixes for SELinux and file permissions
EXTRA_FLAGS=""
SELINUX_SUFFIX=""
if [[ "$(uname)" == "Linux" ]]; then
    # :z is a safe no-op on non-SELinux systems, but essential for Fedora/RHEL
    SELINUX_SUFFIX=",z"
    if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
        # Map host UID to container UID. Standard for Linux Podman.
        EXTRA_FLAGS="--userns=keep-id"
    else
        # For Docker on Linux, we run as the current user to fix host file ownership
        EXTRA_FLAGS="--user $(id -u):$(id -g)"
    fi
fi

"$CONTAINER_ENGINE" run -it --rm \
    $EXTRA_FLAGS \
    --name nids-dev-shell \
    -v "$(pwd):/workspace:z" \
    -v "$HOME/.aws:/home/developer/.aws:z" \
    -v "$HOME/.ssh:/home/developer/.ssh:ro${SELINUX_SUFFIX}" \
    -v "$HOME/.ocp-installer-pull-secret:/home/developer/.ocp-installer-pull-secret:ro${SELINUX_SUFFIX}" \
    -v "${KRB5_HOST_PATH}:/tmp/krb5cc_1000:ro${SELINUX_SUFFIX}" \
    -e NIDS_CONTAINER="true" \
    -e USER="${USER:-}" \
    -e AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}" \
    -e KERBEROS_ID="${KERBEROS_ID:-$USER}" \
    -e OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-}" \
    -e OCP_REGION="${OCP_REGION:-}" \
    "$IMAGE_NAME" "$@"
