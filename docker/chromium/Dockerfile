# RaviOS Chromium - minimal Wayland client with best-effort GPU/VAAPI
# Apt mirrors: Arvan Cloud (including security)

ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN rm -f /etc/apt/sources.list.d/* \
    && printf '%s\n' \
        'deb http://mirror.arvancloud.ir/debian bookworm main contrib non-free non-free-firmware' \
        'deb http://mirror.arvancloud.ir/debian bookworm-updates main contrib non-free non-free-firmware' \
        'deb http://mirror.arvancloud.ir/debian-security bookworm-security main contrib non-free non-free-firmware' \
        > /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        chromium \
        fonts-liberation \
        fonts-noto-core \
        ca-certificates \
        libgl1 \
        libegl1 \
        libgles2 \
        libgbm1 \
        libdrm2 \
        libgl1-mesa-dri \
        mesa-va-drivers \
        mesa-vdpau-drivers \
        mesa-vulkan-drivers \
        libva2 \
        libva-drm2 \
        libva-x11-2 \
        vainfo \
        intel-media-va-driver \
        i965-va-driver \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && rm -rf /usr/share/doc /usr/share/man /usr/share/info \
    && if [ -f /usr/lib/chromium/chrome-sandbox ]; then \
         chmod 4755 /usr/lib/chromium/chrome-sandbox; \
       fi

WORKDIR /root

ENV HOME=/root \
    XDG_RUNTIME_DIR=/tmp/runtime-browser \
    WAYLAND_DISPLAY=wayland-1 \
    XDG_SESSION_TYPE=wayland \
    LIBGL_ALWAYS_SOFTWARE=0 \
    LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri

# --no-sandbox is required inside typical containers.
# --test-type hides the yellow "unsupported flag: --no-sandbox" infobar.
CMD [ \
    "chromium", \
    "--no-sandbox", \
    "--test-type", \
    "--ozone-platform=wayland", \
    "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,CanvasOopRasterization,UseOzonePlatform,AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL", \
    "--ignore-gpu-blocklist", \
    "--enable-gpu-rasterization", \
    "--enable-zero-copy", \
    "--use-gl=angle", \
    "--use-angle=gl", \
    "--disable-gpu-driver-bug-workarounds", \
    "--disable-features=TranslateUI,MediaRouter,UseChromeOSDirectVideoDecoder", \
    "--check-for-update-interval=31536000", \
    "--disable-component-update", \
    "--no-first-run", \
    "--no-default-browser-check", \
    "--disable-sync", \
    "--disable-background-networking" \
]
