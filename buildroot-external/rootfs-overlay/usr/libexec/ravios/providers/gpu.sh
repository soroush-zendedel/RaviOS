#!/bin/sh
# RaviOS GPU resource provider
# Relies on host groups "video" and "render" (RaviOS standard).

provider_gpu_resolve() {
    if [ ! -d /dev/dri ]; then
        echo "ERROR:gpu: /dev/dri not present on host" >&2
        return 1
    fi

    echo "DEVICE:/dev/dri"

    # Standard DRM groups — guaranteed by RaviOS host setup
    echo "GROUP:video"
    echo "GROUP:render"

    echo "ENV:LIBGL_ALWAYS_SOFTWARE=0"
    if [ -d /usr/lib/x86_64-linux-gnu/dri ]; then
        echo "ENV:LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri"
    fi

    return 0
}
