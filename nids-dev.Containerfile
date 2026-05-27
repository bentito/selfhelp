# Use RHEL 9 UBI as the base
FROM registry.access.redhat.com/ubi9/ubi:latest

# Install system dependencies
RUN dnf install -y \
    krb5-workstation \
    git \
    openssh-clients \
    python3-pip \
    tar \
    gzip \
    unzip \
    && dnf clean all

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip ./aws

# Install OpenShift Binaries (oc, openshift-install, ccoctl)
# Note: We use 4.21.10 as the baseline from the current one-shot script
RUN mkdir -p /usr/local/bin && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.21.10/openshift-install-linux-4.21.10.tar.gz | tar -xz -C /usr/local/bin openshift-install && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.21.10/openshift-client-linux-4.21.10.tar.gz | tar -xz -C /usr/local/bin oc && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.21.10/ccoctl-linux-4.21.10.tar.gz | tar -xz -C /usr/local/bin ccoctl && \
    ln -s /usr/local/bin/openshift-install /usr/local/bin/openshift-install-4.21

# Install internal Red Hat SAML tool
# We use the same GIT_SSL_NO_VERIFY trick as the setup.sh
RUN GIT_SSL_NO_VERIFY=true pip install --no-cache-dir git+https://gitlab.cee.redhat.com/compute/aws-automation.git

# Setup developer user
RUN useradd -u 1000 -m developer
USER developer
WORKDIR /workspace

# Kerberos and AWS environment
ENV KRB5CCNAME=FILE:/tmp/krb5cc_1000
ENV PATH="/home/developer/.local/bin:${PATH}"

# Default command
CMD ["/bin/bash"]
