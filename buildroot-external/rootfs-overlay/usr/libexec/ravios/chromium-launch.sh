#!/bin/sh
# Launch Chromium in Docker against the current Wayland session.
# Manual start only:  chromium  |  ravios-app start chromium
#
# Persistent storage (from app.json volumes when present):
#   ravios-chromium-data  -> /data   (profile: history, cookies, ...)
#   ravios-chromium-cache -> /cache  (disk cache, separately clearable)
#
# After an unclean reboot while Chromium was running, Chrome leaves
# SingletonLock (and related files) in the profile volume. The next start
# then exits immediately. We always clear those stale locks before launch.

set -eu

log() {
    echo "ravios-chromium: $*" >&2
}

IMAGE_NAME="ravios-chromium:latest"
IMAGE_TAR="/var/lib/docker/ravios-apps/chromium/image.tar"
APP_JSON="/var/lib/docker/ravios-apps/chromium/app.json"
CONTAINER_NAME="chromium"

# Defaults if manifest is missing
DEFAULT_VOLUMES="ravios-chromium-data:/data ravios-chromium-cache:/cache"

json_get_array() {
    file="$1"
    key="$2"
    [ -r "$file" ] || return 1
    body="$(tr '\n' ' ' < "$file" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p")"
    [ -n "$body" ] || return 1
    echo "$body" | tr ',' '\n' | sed 's/[[:space:]]*"\([^"]*\)".*/\1/' | tr '\n' ' '
}

ensure_image() {
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        return 0
    fi
    if [ -f "$IMAGE_TAR" ]; then
        log "loading image from seed tar"
        docker load -i "$IMAGE_TAR" || return 1
        rm -f "$IMAGE_TAR"
    else
        return 1
    fi
    docker image inspect "$IMAGE_NAME" >/dev/null 2>&1
}

ensure_volume() {
    name="$1"
    [ -n "$name" ] || return 0
    if ! docker volume inspect "$name" >/dev/null 2>&1; then
        log "creating volume $name"
        docker volume create "$name" >/dev/null || return 1
    fi
}

# Remove stale Chromium singleton locks from the profile volume.
# Safe while no Chromium container is running (caller ensures that).
clear_stale_profile_locks() {
    data_vol=""
    for vol in $1; do
        case "$vol" in
            *:/data) data_vol="${vol%%:*}" ;;
        esac
    done
    [ -n "$data_vol" ] || return 0

    log "clearing stale Chromium profile locks on volume $data_vol"
    # Use the browser image itself (has a shell); ignore failures if volume empty.
    docker run --rm \
        -v "$data_vol:/data" \
        --entrypoint /bin/sh \
        "$IMAGE_NAME" \
        -c 'rm -f /data/SingletonLock /data/SingletonCookie /data/SingletonSocket \
               /data/lockfile /data/.org.chromium.Chromium.* 2>/dev/null; \
            rm -f /data/Default/LOCK /data/Default/lockfile 2>/dev/null; \
            mkdir -p /data/Downloads; \
            true' >/dev/null 2>&1 || true
}

if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    log "WAYLAND_DISPLAY or XDG_RUNTIME_DIR not set - run from a graphical session"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    log "docker not installed"
    exit 1
fi

SOCKET_PATH="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
if [ ! -S "$SOCKET_PATH" ]; then
    log "Wayland socket not found: $SOCKET_PATH"
    exit 1
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    log "already running"
    exit 0
fi

if ! ensure_image; then
    log "image not available (is Docker Data seeded and loaded?)"
    exit 1
fi

# Resolve volumes from manifest (fallback to defaults)
VOL_LIST=""
if [ -r "$APP_JSON" ]; then
    VOL_LIST="$(json_get_array "$APP_JSON" volumes 2>/dev/null || true)"
fi
if [ -z "$VOL_LIST" ]; then
    VOL_LIST="$DEFAULT_VOLUMES"
fi

VOLUME_ARGS=""
for vol in $VOL_LIST; do
    vname="${vol%%:*}"
    ensure_volume "$vname" || {
        log "cannot ensure volume $vname"
        exit 1
    }
    VOLUME_ARGS="$VOLUME_ARGS -v $vol"
done

# Always remove any leftover container, then clear locks from unclean shutdown.
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
clear_stale_profile_locks "$VOL_LIST"

GROUP_ARGS="--group-add video"
VOLUMES="-v ${SOCKET_PATH}:/tmp/runtime-browser/${WAYLAND_DISPLAY}"
if [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]; then
    VOLUMES="$VOLUMES -v ${XDG_RUNTIME_DIR}/pipewire-0:/tmp/runtime-browser/pipewire-0"
fi

DEVICE_ARGS=""
if [ -d /dev/dri ]; then
    DEVICE_ARGS="--device /dev/dri"
fi

if ! docker network inspect ravios-net >/dev/null 2>&1; then
    docker network create ravios-net >/dev/null 2>&1 || true
fi

# shellcheck disable=SC2086
cid="$(docker run -d --rm \
    --name "$CONTAINER_NAME" \
    --network ravios-net \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    --cap-add SYS_ADMIN \
    --cap-add SYS_PTRACE \
    $DEVICE_ARGS \
    $GROUP_ARGS \
    $VOLUME_ARGS \
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
    --user-data-dir=/data \
    --disk-cache-dir=/cache \
    --download-default-directory=/data/Downloads \
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
    "file:///usr/share/ravios/webui-wait.html")"

# Brief settle check: if Chromium exits at once (stale lock / display), report it.
sleep 2
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
    log "container exited immediately after start (id=${cid:-unknown})"
    log "tip: profile locks are cleared on each start; if this persists, check Wayland session"
    exit 1
fi

log "started (profile=/data cache=/cache)"
