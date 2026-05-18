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

*(Note: The setup script bypasses SSL verification internally during the pip installation because Red Hat's internal GitLab instance uses self-signed certificates).*

## 3. Configuration & Usage

The `ocp-cluster-one-shot-4.21.sh` script handles everything automatically, including AWS authentication. 

By default, the script assumes your Kerberos ID is the same as your local system `$USER`. It also requires the NIDS AWS Account ID to be explicitly set. 

Please request the **NIDS Dev AWS Account ID** from a team member on Slack, and export it in your shell profile (e.g., `~/.zshrc` or `~/.bashrc`):

```bash
export AWS_ACCOUNT_ID="<account_id_from_slack>"
export KERBEROS_ID="johndoe" # Only needed if different from your laptop username
```

### Launching a Cluster

Simply run the one-shot script:

```bash
./ocp-cluster-one-shot-4.21.sh
```

**What happens under the hood:**
1.  **Clean Slate:** The script wipes your local `ocp-install-dir` to ensure no stale state interferes with the new build.
2.  **Kerberos Authentication:** The script checks your Kerberos ticket. If you don't have an active ticket, it will prompt you for your Red Hat Kerberos password.
3.  **SAML Federation:** It silently calls the `aws-saml.py` tool from the virtual environment, requests the `admin` role for the NIDS team AWS account (using the `$AWS_ACCOUNT_ID` variable), and saves the temporary credentials.
4.  **IAM Provisioning (ccoctl):** It uses Podman to run the OpenShift Cloud Credential Operator (`ccoctl`) against AWS. This creates the exact IAM roles the cluster needs to function in STS mode.
5.  **Thumbprint Patching:** Because internal Red Hat proxies can alter certificate chains, AWS STS sometimes rejects the OIDC tokens. The script fetches the live SSL certificate fingerprint of your new AWS S3 bucket and automatically patches the IAM Provider to guarantee STS trust.
6.  **Cluster Deployment:** It creates a unique cluster name based on your `$USER` and a local counter, configures the OpenShift installer with `credentialsMode: Manual`, injects the `ccoctl` secrets, and starts the deployment.

### Tearing Down a Cluster

To destroy the cluster and clean up AWS resources, use the teardown script:

```bash
./ocp-cluster-teardown.sh
```

## Troubleshooting

*   **Missing Dependencies:** If `./setup.sh` fails during the `pip install` phase, ensure you have the C-level development headers for LDAP and Kerberos installed on your system (see prerequisites).
*   **Authentication Failures:** If you get `InvalidClientTokenId` or similar AWS errors, your SAML session may have expired in the middle of a command. Run the cluster deployment script again; it will automatically refresh the token.
*   **Pull Secret Errors:** Ensure the pull secret file exists at `~/.ocp-installer-pull-secret` and contains valid, unformatted JSON.