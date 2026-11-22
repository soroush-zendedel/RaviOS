FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/root

# Install Buildroot and Linux kernel build dependencies
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
    ccache \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Configure UTF-8 locale
RUN locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

WORKDIR /workspace

USER root

CMD ["/bin/bash"]


# Keep the Buildroot initializer inside the development image.
# Buildroot source itself is NOT copied into the image or mounted from Windows;
# it is initialized directly in the persistent Docker named volume.
COPY docker/development/initialize-buildroot.sh /usr/local/bin/ravios-initialize-buildroot
RUN chmod 0755 /usr/local/bin/ravios-initialize-buildroot
