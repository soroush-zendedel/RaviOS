#!/bin/sh
# RaviOS Display resource provider
# Host must provide standard groups (see S05ravios-groups / post-build).

provider_display_resolve() {
    if [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ]; then
        echo "ERROR:display: WAYLAND_DISPLAY or XDG_RUNTIME_DIR not set" >&2
        return 1
    fi

    SOCKET_PATH="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    if [ ! -S "$SOCKET_PATH" ]; then
        echo "ERROR:display: Wayland socket not found at $SOCKET_PATH" >&2
        return 1
    fi

    CONTAINER_RUNTIME="/tmp/runtime-ravios"
    echo "VOLUME:${SOCKET_PATH}:${CONTAINER_RUNTIME}/${WAYLAND_DISPLAY}"
    echo "ENV:WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
    echo "ENV:XDG_RUNTIME_DIR=${CONTAINER_RUNTIME}"
    echo "ENV:XDG_SESSION_TYPE=wayland"

    # Standard host groups (created by RaviOS at image build / boot)
    echo "GROUP:video"

    return 0
}
