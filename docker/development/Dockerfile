FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
    -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g' \
    /etc/apt/sources.list.d/ubuntu.sources

# Bootstrap CA certificates
RUN apt-get -o Acquire::https::Verify-Peer=false update && \
    apt-get -o Acquire::https::Verify-Peer=false install -y ca-certificates && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*
    
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    binutils \
    gcc \
    g++ \
    make \
    bash \
    git \
    wget \
    curl \
    ca-certificates \
    which \
    sed \
    diffutils \
    patch \
    perl \
    gzip \
    bzip2 \
    tar \
    cpio \
    unzip \
    rsync \
    file \
    bc \
    findutils \
    gawk \
    python3 \
    libncurses-dev \
    libssl-dev \
    libelf-dev \
    flex \
    bison \
    xz-utils \
    zstd \
    lz4 \
    device-tree-compiler \
    && rm -rf /var/lib/apt/lists/*

ARG RAVIOS_UID=1000
ARG RAVIOS_GID=1000

RUN if ! getent group ${RAVIOS_GID} >/dev/null; then \
        groupadd --gid ${RAVIOS_GID} builder; \
    fi && \
    GROUP_NAME=$(getent group ${RAVIOS_GID} | cut -d: -f1) && \
    if ! getent passwd ${RAVIOS_UID} >/dev/null; then \
        useradd --uid ${RAVIOS_UID} \
                --gid ${RAVIOS_GID} \
                --create-home \
                --home-dir /home/builder \
                --shell /bin/bash builder; \
    fi && \
    USER_NAME=$(getent passwd ${RAVIOS_UID} | cut -d: -f1) && \
    usermod -aG ${GROUP_NAME} ${USER_NAME}

ENV HOME=/home/builder

WORKDIR /workspace

USER ${RAVIOS_UID}

CMD ["/bin/bash"]