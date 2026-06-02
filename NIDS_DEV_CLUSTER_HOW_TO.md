# NIDS Dev Cluster Setup & Usage Guide

This guide explains how to bootstrap the OpenShift cluster deployment scripts on a fresh laptop. The NIDS team uses an automated Kerberos/SAML flow to fetch temporary AWS credentials securely without relying on long-lived IAM keys.

## 1. Prerequisites

Before running the automation scripts, ensure your laptop is ready:

*   **VPN Connection:** You must be connected to the Red Hat corporate VPN to access the internal GitLab repository and Kerberos endpoints.
*   **System Dependencies:** 
    *   **Podman or Docker:** This is the primary requirement. All other tools (AWS CLI, OpenShift binaries, Python) are bundled in a container.
    *   **kinit:** Required on the host to request Kerberos tickets.
        *   **Mac (Homebrew):** `brew install krb5 podman` (or `docker`)
        *   **Linux (Fedora/RHEL):** `sudo dnf install krb5-workstation podman` (or `docker`)
*   **OpenShift Pull Secret:**
    *   Download your pull secret from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret).
    *   Save it exactly at: `~/.ocp-installer-pull-secret`
*   **SSH Key:**
    *   Ensure you have a default SSH key generated. If you don't, run: `ssh-keygen -t ed25519`
*   **Container VM Time Synchronization:**
    *   The AWS STS authentication process strictly requires accurate timestamps. If your laptop has recently slept or been suspended, the container VM's clock may drift.
    *   **Podman Users:** The script handles this automatically by syncing the clock using `date -s`. If it fails, run: `podman machine stop && podman machine start`.
    *   **Docker Users:** Ensure your Docker Desktop clock is accurate (usually fixed by restarting Docker Desktop).

## 2. Bootstrapping the Environment

Run the setup script provided in this repository. It will verify your prerequisites and build the `nids-dev` Podman image.

```bash
./setup.sh
```

*(Note: The setup script builds a RHEL 9 UBI container that includes all necessary CLI tools and the internal Red Hat `aws-automation` SAML tool).*

## 3. Configuration & Usage

The NIDS environment is fully automated. You can run the deployment scripts directly from your host machine; they will automatically detect the environment and re-execute themselves inside the Podman container if necessary.

### Optional: Password-less Kerberos (Automation)

If you wish to avoid the interactive Kerberos password prompt, you can save the password in a plain text file at `~/.krb-passwd`. This can be dangerous, use with care.

```bash
echo "your_password" > ~/.krb-passwd
chmod 600 ~/.krb-passwd
```

The deployment scripts will automatically detect this file and use it for authentication.

### Environment Variables

The deployment scripts rely on several environment variables. You must export the required variables in your shell or add them to your `~/.bashrc` or `~/.zshrc`.

**Required:**
*   `AWS_ACCOUNT_ID`: The 12-digit AWS Account ID for the NIDS Team Dev account. Ask the team on Slack if you do not have this.

**Optional Overrides (Defaults provided):**
*   `OCP_REGION`: The AWS region to deploy into (Defaults to `us-west-2`).
*   `OCP_BASE_DOMAIN`: The base Route53 domain for the cluster (Defaults to `nids-dev.devcluster.openshift.com`).
*   `OCP_CLUSTER_NAME`: Override the auto-generated sequential cluster name.
*   `KERBEROS_ID`: Your Red Hat Kerberos ID (Defaults to your system `$USER`).
*   `AWS_PROFILE`: The local AWS profile name to configure (Defaults to `nids-dev`).
*   `SAML_ROLE_NAME`: The AWS IAM role to request via SAML (Defaults to `admin`).
*   `SSH_PUBKEY_PATH`: The path to the SSH public key for cluster access (Defaults to `~/.ssh/id_ed25519.pub`). *Note: Since the script runs in a container, the key must reside within your host's `~/.ssh` directory to be visible.*
*   `CONTAINER_ENGINE`: Choose between `podman` and `docker` (Defaults to `podman`).

### Launching a Cluster

Simply run the one-shot script. By default, it will deploy **OpenShift 4.21**.

```bash
./ocp-cluster-one-shot.sh
```

To deploy a specific version (e.g., **4.19**), pass it as the first argument:

```bash
./ocp-cluster-one-shot.sh 4.19
```

**What happens:**
1.  **Auto-Detection:** The script detects it is running on the host and calls `./nids-run.sh`.
2.  **Container Entry:** The container starts, mounting your host's Kerberos ticket, AWS config, and SSH keys. If using Podman, it also automatically ensures your VM clock is synced to prevent AWS authentication errors.
3.  **AWS Authentication:** The script (now inside the container) uses the host's ticket to refresh AWS credentials via `aws-saml.py`.
4.  **Provisioning & Deployment:** The script uses the pre-installed Linux binaries to provision IAM roles and launch the cluster.

### Manual Container Shell

If you need to run manual commands or debug, you can still enter the container shell directly:

```bash
./nids-run.sh
```

### Tearing Down a Cluster

To destroy the cluster and clean up AWS resources, use the teardown script:

```bash
./ocp-cluster-teardown.sh
```

## Troubleshooting

*   **Missing Dependencies:** If `./setup.sh` fails during the `pip install` phase, ensure you have the C-level development headers for LDAP and Kerberos installed on your system (see prerequisites).
*   **Authentication Failures:** If you get `InvalidClientTokenId` or similar AWS errors, your SAML session may have expired in the middle of a command. Run the cluster deployment script again; it will automatically refresh the token.
*   **Pull Secret Errors:** Ensure the pull secret file exists at `~/.ocp-installer-pull-secret` and contains valid, unformatted JSON.
