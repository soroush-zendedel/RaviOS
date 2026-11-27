#!/bin/sh
# RaviOS Network resource provider
# Creates and manages named shared networks declared in application manifests.
# Shared networks are reference-counted so that stopping one app does not
# destroy a network still used by others.

NETWORK_STATE_DIR="/var/lib/ravios/apps/networks"

provider_network_ensure() {
    net_name="$1"
    mode="${2:-shared}"

    [ -n "$net_name" ] || return 0

    mkdir -p "$NETWORK_STATE_DIR"

    if ! docker network inspect "$net_name" >/dev/null 2>&1; then
        if ! docker network create "$net_name" >/dev/null 2>&1; then
            echo "ERROR:network: failed to create $net_name" >&2
            return 1
        fi
    fi

    # Simple reference tracking for shared networks.
    if [ "$mode" = "shared" ]; then
        ref_file="$NETWORK_STATE_DIR/${net_name}.refs"
        # The caller is expected to pass the application name as $3 when available.
        app_ref="${3:-unknown}"
        if [ -f "$ref_file" ]; then
            grep -qxF "$app_ref" "$ref_file" 2>/dev/null || echo "$app_ref" >> "$ref_file"
        else
            echo "$app_ref" > "$ref_file"
        fi
    fi

    echo "NETWORK:$net_name"
    return 0
}

provider_network_release() {
    net_name="$1"
    app_ref="${2:-unknown}"

    [ -n "$net_name" ] || return 0
    ref_file="$NETWORK_STATE_DIR/${net_name}.refs"
    [ -f "$ref_file" ] || return 0

    # Remove this app's reference.
    tmp="$(mktemp)"
    grep -vxF "$app_ref" "$ref_file" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$ref_file"

    # If no references remain, the network may be removed by a higher-level
    # cleanup policy. We deliberately do NOT auto-remove here so that shared
    # networks stay available for other apps and for future starts.
    if [ ! -s "$ref_file" ]; then
        rm -f "$ref_file"
        # Intentionally leave the Docker network in place (shared resource
        # lifecycle is independent of any single application).
    fi
    return 0
}
