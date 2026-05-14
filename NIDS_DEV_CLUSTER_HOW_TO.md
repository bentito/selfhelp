# NIDS Dev Cluster Setup & Usage Guide

This guide explains how to bootstrap the OpenShift cluster deployment scripts on a fresh laptop. The NIDS team uses an automated Kerberos/SAML flow to fetch temporary AWS credentials securely without relying on long-lived IAM keys.

## 1. Prerequisites

Before running the automation scripts, ensure your laptop is ready:

*   **VPN Connection:** You must be connected to the Red Hat corporate VPN to access the internal GitLab repository and Kerberos endpoints.
*   **System Dependencies:** You need `kinit` to request Kerberos tickets.
    *   **Mac (Homebrew):** `brew install krb5 awscli`
    *   **Linux (Fedora/RHEL):** `sudo dnf install krb5-devel python3-devel openldap-devel awscli`
*   **OpenShift Pull Secret:**
    *   Download your pull secret from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret).
    *   Save it exactly at: `~/.ocp-installer-pull-secret`
*   **SSH Key:**
    *   Ensure you have a default SSH key generated. If you don't, run: `ssh-keygen -t ed25519`

## 2. Bootstrapping the Environment

Run the setup script provided in this repository. It will verify your prerequisites, create an isolated Python virtual environment, and install the internal Red Hat `aws-automation` SAML tool.

```bash
./setup.sh
```

*(Note: The setup script bypasses SSL verification internally during the pip installation because corporate GitLab instances often use self-signed certificates).*

## 3. Configuration & Usage

The `ocp-cluster-one-shot-4.21.sh` script handles everything automatically, including AWS authentication. 

By default, the script assumes your Kerberos ID is the same as your local system `$USER`. If your Red Hat Kerberos ID is different from your laptop username, export it first:

```bash
export KERBEROS_ID="johndoe"
```

### Launching a Cluster

Simply run the one-shot script:

```bash
./ocp-cluster-one-shot-4.21.sh
```

**What happens under the hood:**
1.  **Kerberos Authentication:** The script checks your Kerberos ticket. If you don't have an active ticket, it will prompt you for your Red Hat Kerberos password.
2.  **SAML Federation:** It silently calls the `aws-saml.py` tool from the virtual environment, requests the `admin` role for the NIDS team AWS account (`<your-aws-account-id>`), and saves the temporary credentials.
3.  **Cluster Deployment:** It creates a unique cluster name based on your `$USER` and the date, configures the OpenShift installer with `credentialsMode: Manual` (to accept the temporary SAML tokens), and starts the deployment.

### Tearing Down a Cluster

To destroy the cluster and clean up AWS resources, use the teardown script:

```bash
./ocp-cluster-teardown.sh
```

## Troubleshooting

*   **Missing Dependencies:** If `./setup.sh` fails during the `pip install` phase, ensure you have the C-level development headers for LDAP and Kerberos installed on your system (see prerequisites).
*   **Authentication Failures:** If you get `InvalidClientTokenId` or similar AWS errors, your SAML session may have expired in the middle of a command. Run the cluster deployment script again; it will automatically refresh the token.
*   **Pull Secret Errors:** Ensure the pull secret file exists at `~/.ocp-installer-pull-secret` and contains valid, unformatted JSON.