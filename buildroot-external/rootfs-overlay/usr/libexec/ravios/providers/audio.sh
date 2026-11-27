#!/bin/sh
# RaviOS Audio resource provider
# Relies on host group "audio" (RaviOS standard).

provider_audio_resolve() {
    if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
        echo "ERROR:audio: XDG_RUNTIME_DIR not set" >&2
        return 1
    fi

    PW_SOCKET="${XDG_RUNTIME_DIR}/pipewire-0"
    if [ ! -S "$PW_SOCKET" ]; then
        echo "WARN:audio: PipeWire socket not found at $PW_SOCKET" >&2
        return 0
    fi

    CONTAINER_RUNTIME="/tmp/runtime-ravios"
    echo "VOLUME:${PW_SOCKET}:${CONTAINER_RUNTIME}/pipewire-0"
    echo "ENV:PIPEWIRE_RUNTIME_DIR=${CONTAINER_RUNTIME}"
    echo "ENV:XDG_RUNTIME_DIR=${CONTAINER_RUNTIME}"

    echo "GROUP:audio"

    return 0
}
