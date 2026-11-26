#!/bin/sh
# RaviOS: start Chromium as soon as Wayland is up (image preloaded at boot).
# Named 05- so it starts before Foot (10-foot.sh) for closer on-screen timing.

set -eu

log() {
    echo "ravios-chromium: $*" >&2
}

IMAGE_NAME="ravios-chromium:latest"
IMAGE_TAR="/usr/share/ravios/docker-images/ravios-chromium.tar"
CONTAINER_NAME="chromium"

ensure_image_fallback() {
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        return 0
    fi
    # Fallback if S70 did not run or failed
    if [ -f "$IMAGE_TAR" ]; then
        log "image missing at session start - loading tar (fallback)"
        docker load -i "$IMAGE_TAR" || return 1
    else
        return 1
    fi
    docker image inspect "$IMAGE_NAME" >/dev/null 2>&1
}

start_container() {
    SOCKET_PATH="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"

    GROUP_ARGS="--group-add video"

    VOLUMES="-v ${SOCKET_PATH}:/tmp/runtime-browser/${WAYLAND_DISPLAY}"
    if [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]; then
        VOLUMES="$VOLUMES -v ${XDG_RUNTIME_DIR}/pipewire-0:/tmp/runtime-browser/pipewire-0"
    fi

    DEVICE_ARGS=""
    if [ -d /dev/dri ]; then
        DEVICE_ARGS="--device /dev/dri"
    fi

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    # Ensure shared network so Chromium can reach Open WebUI by name.
    if ! docker network inspect ravios-net >/dev/null 2>&1; then
        docker network create ravios-net >/dev/null 2>&1 || true
    fi

    # shellcheck disable=SC2086
    # Args after the image replace CMD; keep the same flags as docker/chromium/Dockerfile
    # and open Open WebUI automatically on the shared network.
    docker run -d --rm \
        --name "$CONTAINER_NAME" \
        --network ravios-net \
        --security-opt seccomp=unconfined \
        --security-opt apparmor=unconfined \
        --cap-add SYS_ADMIN \
        --cap-add SYS_PTRACE \
        $DEVICE_ARGS \
        $GROUP_ARGS \
        -e WAYLAND_DISPLAY \
        -e XDG_RUNTIME_DIR=/tmp/runtime-browser \
        -e XDG_SESSION_TYPE=wayland \
        -e LANG=C.UTF-8 \
        -e LIBGL_ALWAYS_SOFTWARE=0 \
        -e LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri \
        $VOLUMES \
        --ipc=host \
        "$IMAGE_NAME" \
        chromium \
        --no-sandbox \
        --test-type \
        --ozone-platform=wayland \
        --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,CanvasOopRasterization,UseOzonePlatform,AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL \
        --ignore-gpu-blocklist \
        --enable-gpu-rasterization \
        --enable-zero-copy \
        --use-gl=angle \
        --use-angle=gl \
        --disable-gpu-driver-bug-workarounds \
        --disable-features=TranslateUI,MediaRouter,UseChromeOSDirectVideoDecoder \
        --check-for-update-interval=31536000 \
        --disable-component-update \
        --no-first-run \
        --no-default-browser-check \
        --disable-sync \
        --disable-background-networking \
        "http://ravios-webui:8080"
}

# --- main ---

if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    log "WAYLAND_DISPLAY or XDG_RUNTIME_DIR not set - skip"
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    log "docker not installed - skip"
    exit 0
fi

SOCKET_PATH="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
if [ ! -S "$SOCKET_PATH" ]; then
    log "Wayland socket not found: $SOCKET_PATH - skip Chromium"
    exit 0
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    log "already running"
    exit 0
fi

if ! ensure_image_fallback; then
    log "image not available"
    exit 0
fi

if start_container; then
    log "started"
else
    log "failed to start container"
fi
