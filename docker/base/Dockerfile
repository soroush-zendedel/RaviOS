FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    tzdata \
    locales \
    curl \
    wget \
    xz-utils \
    unzip \
    zip \
    bash \
    coreutils \
    procps \
    iproute2 \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/ravios

CMD ["/bin/bash"]
