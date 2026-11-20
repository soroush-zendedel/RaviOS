#!/bin/sh

set -eu

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "ravios-foot: WAYLAND_DISPLAY is not set" >&2
    exit 1
fi

exec /usr/bin/foot
