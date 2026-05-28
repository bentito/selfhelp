# NIDS Dev Cluster Setup & Usage Guide

This guide explains how to bootstrap the OpenShift cluster deployment scripts on a fresh laptop. The NIDS team uses an automated Kerberos/SAML flow to fetch temporary AWS credentials securely without relying on long-lived IAM keys.

## 1. Prerequisites

Before running the automation scripts, ensure your laptop is ready:

*   **VPN Connection:** You must be connected to the Red Hat corporate VPN to access the internal GitLab repository and Kerberos endpoints.
*   **System Dependencies:** 
    *   **Podman:** This is the primary requirement. All other tools (AWS CLI, OpenShift binaries, Python) are bundled in a container.
    *   **kinit:** Required on the host to request Kerberos tickets.
        *   **Mac (Homebrew):** `brew install krb5 podman`
        *   **Linux (Fedora/RHEL):** `sudo dnf install krb5-workstation podman`
*   **OpenShift Pull Secret:**
    *   Download your pull secret from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret).
    *   Save it exactly at: `~/.ocp-installer-pull-secret`
*   **SSH Key:**
    *   Ensure you have a default SSH key generated. If you don't, run: `ssh-keygen -t ed25519`
*   **Podman Time Synchronization:**
    *   The AWS STS authentication process strictly requires accurate timestamps. If your laptop has recently slept or been suspended, the Podman VM's clock may drift.
    *   **To fix this, always run:** `podman machine stop && podman machine start` before your first cluster deployment of the day.

## 2. Bootstrapping the Environment

Run the setup script provided in this repository. It will verify your prerequisites and build the `nids-dev` Podman image.

```bash
./setup.sh
```

*(Note: The setup script builds a RHEL 9 UBI container that includes all necessary CLI tools and the internal Red Hat `aws-automation` SAML tool).*

## 3. Configuration & Usage

The NIDS environment is fully automated. You can run the deployment scripts directly from your host machine; they will automatically detect the environment and re-execute themselves inside the Podman container if necessary.

### Optional: Password-less Kerberos (Automation)

If you wish to avoid the interactive Kerberos password prompt, you can save your Red Hat password in a plain text file at `~/.krb-passwd`. 

```bash
echo "your_password" > ~/.krb-passwd
chmod 600 ~/.krb-passwd
```

The deployment scripts will automatically detect this file and use it for authentication.

### Launching a Cluster

Simply run the one-shot script for your desired OpenShift version:

```bash
./ocp-cluster-one-shot-4.21.sh
# OR
./ocp-cluster-one-shot-4.19.sh
```

**What happens:**
1.  **Auto-Detection:** The script detects it is running on the host and calls `./nids-run.sh`.
2.  **Container Entry:** The container starts, mounting your host's Kerberos ticket, AWS config, and SSH keys.
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