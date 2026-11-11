# syntax=docker/dockerfile:1
# NVIDIA lists this release in its DGX Spark collection. Build with
# --platform linux/arm64; an x86 image is not a Spark image.
ARG BASE_IMAGE=nvcr.io/nvidia/pytorch:26.10-py3
FROM ${BASE_IMAGE}

USER root
ARG TARGETARCH
ARG CODE_SERVER_VERSION=4.145.2
ARG CODE_SERVER_SHA256=0fa9af7f602536b1e320a17d32bb1a85e4a924fdc09283898f1bea73d2a5c1e7

RUN test "${TARGETARCH}" = arm64 && test "$(dpkg --print-architecture)" = arm64
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl git vim sudo openssh-server supervisor \
        iproute2 iputils-ping locales \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8 \
    && rm -f /etc/ssh/ssh_host_*

# Use the native ARM64 release, including its bundled Node.js. Do not install
# the legacy Node 16 repository or replace NVIDIA's Python/torch packages.
RUN curl --fail --location --retry 3 \
        "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_arm64.deb" \
        --output /tmp/code-server.deb \
    && echo "${CODE_SERVER_SHA256}  /tmp/code-server.deb" | sha256sum --check - \
    && dpkg -i /tmp/code-server.deb \
    && rm /tmp/code-server.deb \
    && code-server --version

# Import checks need no GPU. Actual CUDA execution is tested on the Spark.
RUN python -c 'import platform, torch, jupyterlab, jupyter_server; assert platform.machine() == "aarch64"; print(torch.__version__, torch.version.cuda)' \
    && ln -s "$(command -v jupyter)" /usr/local/bin/ml-dev-jupyter \
    && test -x /opt/nvidia/nvidia_entrypoint.sh

COPY script_files/spark_start.sh /usr/local/bin/ml-dev-start
COPY script_files/spark_healthcheck.py /usr/local/bin/ml-dev-healthcheck
COPY config_files/spark_supervisord.conf /etc/ml-dev/supervisord.conf
COPY config_files/spark_jupyter_config.py /etc/ml-dev/jupyter_server_config.py
RUN chmod 755 /usr/local/bin/ml-dev-start /usr/local/bin/ml-dev-healthcheck

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 SHELL=/bin/bash \
    SSH_PORT=22 JUPYTER_PORT=8888 VSCODE_PORT=8080 ENABLE_SUDO=1
EXPOSE 22 8888 8080
WORKDIR /workspace
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD ["python", "/usr/local/bin/ml-dev-healthcheck"]

# Retain NVIDIA's driver/runtime initialization. An explicit command (e.g.
# `image python -c ...`) bypasses development services, as in the NGC image.
ENTRYPOINT ["/opt/nvidia/nvidia_entrypoint.sh"]
CMD ["/usr/local/bin/ml-dev-start"]
