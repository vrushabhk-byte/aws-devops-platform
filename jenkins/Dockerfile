FROM jenkins/jenkins:lts-jdk21

USER root

ARG TARGETARCH=amd64
ARG KIND_VERSION=v0.29.0
ARG TRIVY_VERSION=0.76.0
ARG TERRAFORM_VERSION=1.16.6

# Install Python, Git, Docker CLI prerequisites and utilities.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        git \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        wget \
        tar \
        gzip \
        unzip \
        jq && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
        > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Install kubectl.
RUN curl -fsSL \
    "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${TARGETARCH}/kubectl" \
    -o /usr/local/bin/kubectl && \
    chmod 0755 /usr/local/bin/kubectl && \
    kubectl version --client

# Install Kind.
RUN curl -fsSL \
    "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${TARGETARCH}" \
    -o /usr/local/bin/kind && \
    chmod 0755 /usr/local/bin/kind && \
    kind version

# Install Trivy.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) TRIVY_ARCH="64bit" ;; \
        arm64) TRIVY_ARCH="ARM64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL \
        "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" \
        -o /tmp/trivy.tar.gz; \
    tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy; \
    chmod 0755 /usr/local/bin/trivy; \
    rm -f /tmp/trivy.tar.gz; \
    /usr/local/bin/trivy --version

# Install Terraform.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) TERRAFORM_ARCH="amd64" ;; \
        arm64) TERRAFORM_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip" \
        -o /tmp/terraform.zip; \
    unzip /tmp/terraform.zip -d /tmp/terraform; \
    install -m 0755 /tmp/terraform/terraform /usr/local/bin/terraform; \
    rm -rf /tmp/terraform /tmp/terraform.zip; \
    terraform version

# Allow Python virtual environments.
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

USER jenkins
