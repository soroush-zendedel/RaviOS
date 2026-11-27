#!/bin/sh
# RaviOS Volume resource provider
# Creates and manages application storage declared in manifests.
# Persistent volumes are never deleted on application stop/remove.

provider_volume_ensure() {
    # Argument forms supported:
    #   "name"
    #   "name:target"
    #   JSON-style objects are expanded by the runtime before calling us.
    entry="$1"
    name="${entry%%:*}"
    [ -n "$name" ] || return 0

    if ! docker volume inspect "$name" >/dev/null 2>&1; then
        if ! docker volume create "$name" >/dev/null 2>&1; then
            echo "ERROR:volume: failed to create $name" >&2
            return 1
        fi
    fi

    # Emit the mount specification for the runtime.
    # If a target path was given, keep it; otherwise the runtime decides.
    if [ "$name" != "$entry" ]; then
        target="${entry#*:}"
        echo "VOLUME:${name}:${target}"
    else
        echo "VOLUME:${name}"
    fi
    return 0
}

# Volumes marked persistent=true are never removed by the runtime.
# Temporary volumes may be cleaned by a future garbage-collection pass.
provider_volume_release() {
    # No-op for the current design: we never delete volumes automatically.
    return 0
}
