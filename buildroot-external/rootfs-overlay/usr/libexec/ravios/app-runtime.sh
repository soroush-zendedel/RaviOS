#!/bin/sh
# RaviOS Application Runtime – common library
# Sourced by /usr/bin/ravi
#
# Implements the generic, manifest-driven execution model described in
# docs/development/application-manifast.md.
#
# No application-specific launch scripts. Every app that supplies a valid
# manifest is started through the same code path.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SEED_ROOT="${RAVIOS_SEED_ROOT:-/var/lib/docker/ravios-apps}"
STATE_DIR="${RAVIOS_STATE_DIR:-/var/lib/ravios/apps}"
PROVIDER_DIR="/usr/libexec/ravios/providers"
STATUS_FILE="/var/lib/ravios/docker-data/status"
CLI_LINK_DIR="/usr/bin"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log()  { echo "ravios-app: $*" >&2; }
warn() { echo "ravios-app: WARN: $*" >&2; }
err()  { echo "ravios-app: ERROR: $*" >&2; }

# ---------------------------------------------------------------------------
# Minimal JSON helpers (BusyBox / POSIX sed friendly)
# ---------------------------------------------------------------------------
json_get() {
    file="$1"
    key="$2"
    [ -r "$file" ] || return 1
    val="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | head -1)"
    if [ -n "$val" ]; then printf '%s\n' "$val"; return 0; fi
    val="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([^,[:space:]}]*\).*/\1/p" "$file" | head -1)"
    if [ -n "$val" ]; then printf '%s\n' "$val"; return 0; fi
    return 1
}

json_get_array() {
    file="$1"
    key="$2"
    [ -r "$file" ] || return 1
    body="$(tr '\n' ' ' < "$file" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p")"
    [ -n "$body" ] || return 1
    echo "$body" | tr ',' '\n' | sed 's/[[:space:]]*"\([^"]*\)".*/\1/' | tr '\n' ' '
}

json_resource_bool() {
    file="$1"
    key="$2"
    val="$(tr '\n' ' ' < "$file" | sed -n "s/.*\"resources\"[[:space:]]*:[[:space:]]*{[^}]*\"$key\"[[:space:]]*:[[:space:]]*\([^,[:space:]}]*\).*/\1/p" | head -1)"
    if [ -n "$val" ]; then
        printf '%s\n' "$val"
        return 0
    fi
    json_get "$file" "$key"
}

json_resource_list() {
    file="$1"
    key="$2"
    [ -r "$file" ] || return 1
    tr '\n' ' ' < "$file" | \
        sed -n "s/.*\"resources\"[[:space:]]*:[[:space:]]*{.*\"$key\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" | \
        tr ',' '\n' | \
        sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | \
        while read -r n; do
            [ -n "$n" ] && printf '%s\n' "$n"
        done
}

json_volume_target() {
    file="$1"
    volname="$2"
    [ -r "$file" ] || return 1
    tr '\n' ' ' < "$file" | \
        sed -n "s/.*\"name\"[[:space:]]*:[[:space:]]*\"$volname\"[[:space:]]*,[[:space:]]*\"target\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | \
        head -1
}

# Emit each element of the "command" array on its own line
json_command_args() {
    # Emit each element of the JSON "command" string array on its own line.
    # Uses a small state-machine so commas inside values and later JSON
    # sections (pre_start, environment, ...) never leak into the result.
    file="$1"
    [ -r "$file" ] || return 1

    tr '\n' ' ' < "$file" | awk '
    {
        if (!match($0, /"command"[[:space:]]*:[[:space:]]*\[/))
            exit 1
        s = substr($0, RSTART + RLENGTH)
        depth = 1
        in_str = 0
        esc = 0
        tok = ""
        n = length(s)
        for (i = 1; i <= n && depth > 0; i++) {
            c = substr(s, i, 1)
            if (in_str) {
                if (esc) { tok = tok c; esc = 0; continue }
                if (c == "\\") { esc = 1; continue }
                if (c == "\"") { print tok; tok = ""; in_str = 0; continue }
                tok = tok c
                continue
            }
            if (c == "\"") { in_str = 1; tok = ""; continue }
            if (c == "[") { depth++; continue }
            if (c == "]") { depth--; continue }
        }
    }'
}



# ---------------------------------------------------------------------------
# Docker readiness
# ---------------------------------------------------------------------------
docker_ready() {
    command -v docker >/dev/null 2>&1 || return 1
    docker info >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Host group baseline — standard names used by providers
# ---------------------------------------------------------------------------
# Providers emit GROUP:video / GROUP:render / GROUP:audio by name (standard
# Linux desktop convention). RaviOS must ensure these exist in /etc/group
# before Docker --group-add runs. Creation is idempotent and safe to call
# from the runtime on every start (in addition to S05 + post-build).

ensure_host_group() {
    name="$1"
    gid="$2"
    [ -n "$name" ] && [ -n "$gid" ] || return 0
    if grep -q "^${name}:" /etc/group 2>/dev/null; then
        return 0
    fi
    if command -v addgroup >/dev/null 2>&1; then
        addgroup -g "$gid" -S "$name" 2>/dev/null && return 0
        addgroup -g "$gid" "$name" 2>/dev/null && return 0
    fi
    if command -v groupadd >/dev/null 2>&1; then
        groupadd -g "$gid" "$name" 2>/dev/null && return 0
    fi
    # Last resort: append to /etc/group (requires root; RaviOS app start runs as root)
    if [ -w /etc/group ] || [ "$(id -u 2>/dev/null)" = "0" ]; then
        echo "${name}:x:${gid}:" >> /etc/group 2>/dev/null && return 0
    fi
    warn "could not create host group '$name' ($gid)"
    return 1
}

ensure_ravios_host_groups() {
    ensure_host_group video 44
    ensure_host_group render 110
    ensure_host_group audio 29
    ensure_host_group pipewire 122
    ensure_host_group input 104
    # Best-effort DRM node ownership so group membership is meaningful
    if [ -d /dev/dri ]; then
        for node in /dev/dri/card*; do
            [ -e "$node" ] || continue
            chgrp video "$node" 2>/dev/null || true
            chmod 0660 "$node" 2>/dev/null || true
        done
        for node in /dev/dri/renderD*; do
            [ -e "$node" ] || continue
            chgrp render "$node" 2>/dev/null || true
            chmod 0666 "$node" 2>/dev/null || true
        done
    fi
}

host_group_exists() {
    g="$1"
    [ -n "$g" ] || return 1
    case "$g" in
        *[!0-9]*)
            if command -v getent >/dev/null 2>&1; then
                getent group "$g" >/dev/null 2>&1 && return 0
            fi
            grep -q "^${g}:" /etc/group 2>/dev/null
            ;;
        *) return 0 ;;  # numeric GID always "exists" for Docker
    esac
}

# Well-known GIDs (Debian/Linux desktop ABI) — fallback only when the host
# has no matching /etc/group entry.
#   video  — DRM card nodes / classic GPU access (host may use e.g. 28)
#   render — /dev/dri/renderD*
#   audio  — sound / PipeWire
group_default_gid() {
    case "$1" in
        video|ravios-gpu-group|ravios-display-group) printf '%s\n' "44" ;;
        render)                                      printf '%s\n' "110" ;;
        audio|ravios-audio-group)                    printf '%s\n' "29" ;;
        pipewire)                                    printf '%s\n' "122" ;;
        input)                                       printf '%s\n' "104" ;;
        *)                                           return 1 ;;
    esac
}

# Always return a *numeric* GID for Docker --group-add.
# BusyBox/minimal hosts often make Docker name-lookup fail even when
# /etc/group contains the entry (observed: video:x:28:pipewire still
# yields "Unable to find group video"). Numeric GIDs never hit that path.
resolve_docker_group() {
    token="$1"
    [ -n "$token" ] || return 1

    case "$token" in
        *[!0-9]*) ;;
        *) printf '%s\n' "$token"; return 0 ;;
    esac

    host_name="$token"
    case "$token" in
        ravios-gpu-group|ravios-display-group) host_name="video" ;;
        ravios-audio-group)                    host_name="audio" ;;
    esac

    def_gid="$(group_default_gid "$token" 2>/dev/null || group_default_gid "$host_name" 2>/dev/null || true)"
    if [ -n "$def_gid" ]; then
        ensure_host_group "$host_name" "$def_gid" 2>/dev/null || true
    fi

    gid=""
    if command -v getent >/dev/null 2>&1; then
        gid="$(getent group "$host_name" 2>/dev/null | cut -d: -f3)"
    fi
    if [ -z "$gid" ]; then
        gid="$(awk -F: -v n="$host_name" '$1 == n { print $3; exit }' /etc/group 2>/dev/null)"
    fi

    case "$gid" in
        ""|*[!0-9]*) ;;
        *) printf '%s\n' "$gid"; return 0 ;;
    esac

    if [ -n "$def_gid" ]; then
        printf '%s\n' "$def_gid"
        return 0
    fi
    return 1
}



# ---------------------------------------------------------------------------
# App discovery
# ---------------------------------------------------------------------------
find_app_dir() {
    query="$1"
    [ -d "$SEED_ROOT" ] || return 1
    if [ -d "$SEED_ROOT/$query" ] && [ -f "$SEED_ROOT/$query/app.json" ]; then
        printf '%s\n' "$SEED_ROOT/$query"
        return 0
    fi
    for dir in "$SEED_ROOT"/*; do
        [ -f "$dir/app.json" ] || continue
        n="$(json_get "$dir/app.json" name 2>/dev/null || true)"
        c="$(json_get "$dir/app.json" cli_name 2>/dev/null || true)"
        if [ "$n" = "$query" ] || [ "$c" = "$query" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}


# ---------------------------------------------------------------------------
# Default-template resolution (no per-image manifest file)
# ---------------------------------------------------------------------------
# If an app has no app.json under SEED_ROOT, but a local Docker image matches
# the cli_name, the runtime renders /etc/ravios/app-template.json in a temp
# file and uses that. Changing the system template immediately affects every
# image that has not been explicitly imported (materialised) under SEED_ROOT.

RAVIOS_APP_TEMPLATE="${RAVIOS_APP_TEMPLATE:-/etc/ravios/app-template.json}"
RAVIOS_DEFAULT_NETWORK="${RAVIOS_DEFAULT_NETWORK:-ravios-net}"

sanitize_cli_name() {
    echo "$1" | sed \
        -e 's|.*/||' \
        -e 's/[^a-zA-Z0-9._-]/-/g' \
        -e 's/[.:]/-/g' \
        -e 's/-\+/-/g' \
        -e 's/^-//' \
        -e 's/-$//' \
        | tr '[:upper:]' '[:lower:]'
}


# Render the system template to a temp file; print path to that app.json.
# Caller may keep or discard the file. Not written under SEED_ROOT.
render_default_manifest() {
    cli="$1"
    image_ref="$2"
    vol_name="ravios-data-${cli}"
    TEMPLATE="${RAVIOS_APP_TEMPLATE:-/etc/ravios/app-template.json}"
    out="/tmp/ravios-default-${cli}.json"

    if [ -r "$TEMPLATE" ]; then
        sed \
            -e "s|{{cli_name}}|$cli|g" \
            -e "s|{{image}}|$image_ref|g" \
            -e "s|{{default_network}}|$RAVIOS_DEFAULT_NETWORK|g" \
            -e "s|{{volume_name}}|$vol_name|g" \
            "$TEMPLATE" > "$out"
    else
        cat > "$out" << EOF
{
  "name": "$cli",
  "cli_name": "$cli",
  "version": "auto",
  "image": "$image_ref",
  "container": "$cli",
  "autostart": false,
  "restart": "no",
  "resources": {
    "display": false,
    "gpu": false,
    "audio": false,
    "networks": [ { "name": "$RAVIOS_DEFAULT_NETWORK", "mode": "shared" } ],
    "volumes": [ { "name": "$vol_name", "target": "/data", "persistent": true } ]
  },
  "environment": {},
  "env_from_host": [],
  "description": "Fallback default for $image_ref"
}
EOF
    fi
    printf '%s\n' "$out"
}

# Resolve to a directory that contains app.json:
#   1) real seed dir under SEED_ROOT (custom / imported)
#   2) else virtual: render default template for matching local image
# Prints the directory path. For virtual apps the dir is /tmp/ravios-virt-<cli>
# containing only app.json (ephemeral).
resolve_app_dir() {
    query="$1"
    if dir="$(find_app_dir "$query" 2>/dev/null)"; then
        printf '%s\n' "$dir"
        return 0
    fi

    img=""
    if docker_ready; then
        # Use a temp file to avoid pipeline subshell losing the value
        _imgf="/tmp/ravios-imgmatch.$$"
        : > "$_imgf"
        docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null |             grep -v ':<none>$' | grep -v '^<none>' | while IFS= read -r i; do
            [ -n "$i" ] || continue
            s="$(sanitize_cli_name "$i")"
            if [ "$s" = "$query" ]; then
                printf '%s\n' "$i" > "$_imgf"
                break
            fi
        done
        img="$(cat "$_imgf" 2>/dev/null || true)"
        rm -f "$_imgf"
    fi
    [ -n "$img" ] || return 1

    vdir="/tmp/ravios-virt-${query}"
    mkdir -p "$vdir"
    json="$(render_default_manifest "$query" "$img")"
    cp "$json" "$vdir/app.json"
    printf '%s\n' "$vdir"
    return 0
}


container_state() {
    c="$1"
    if ! docker container inspect "$c" >/dev/null 2>&1; then
        echo "absent"
        return
    fi
    if docker inspect --format '{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
        echo "running"
    else
        echo "stopped"
    fi
}

# ---------------------------------------------------------------------------
# Load resource providers
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
. "$PROVIDER_DIR/display.sh"
# shellcheck source=/dev/null
. "$PROVIDER_DIR/gpu.sh"
# shellcheck source=/dev/null
. "$PROVIDER_DIR/audio.sh"
# shellcheck source=/dev/null
. "$PROVIDER_DIR/network.sh"
# shellcheck source=/dev/null
. "$PROVIDER_DIR/volume.sh"

# ---------------------------------------------------------------------------
# Resource resolution
# ---------------------------------------------------------------------------
resolve_resources() {
    json="$1"
    app_name="$2"
    # Make sure standard groups exist before providers emit GROUP:name
    ensure_ravios_host_groups

    display="$(json_resource_bool "$json" display 2>/dev/null || echo false)"
    gpu="$(json_resource_bool "$json" gpu 2>/dev/null || echo false)"
    audio="$(json_resource_bool "$json" audio 2>/dev/null || echo false)"

    if [ "$display" = "true" ]; then
        provider_display_resolve || return 1
    fi
    if [ "$gpu" = "true" ]; then
        provider_gpu_resolve || return 1
    fi
    if [ "$audio" = "true" ]; then
        provider_audio_resolve || return 1
    fi

    nets="$(json_resource_list "$json" networks)"
    if [ -z "$nets" ]; then
        nets="$(json_get_array "$json" networks 2>/dev/null || true)"
    fi
    for net in $nets; do
        [ -n "$net" ] || continue
        provider_network_ensure "$net" "shared" "$app_name" || return 1
    done

    has_new_vols=false
    for volname in $(json_resource_list "$json" volumes); do
        has_new_vols=true
        target="$(json_volume_target "$json" "$volname")"
        if [ -n "$target" ]; then
            provider_volume_ensure "${volname}:${target}" || return 1
        else
            provider_volume_ensure "$volname" || return 1
        fi
    done

    if [ "$has_new_vols" = false ]; then
        for vol in $(json_get_array "$json" volumes 2>/dev/null || true); do
            [ -n "$vol" ] || continue
            provider_volume_ensure "$vol" || return 1
        done
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Offline model seed (Ollama etc.)
# ---------------------------------------------------------------------------
# Reads extra.model_archive / extra.model_volume from the manifest and extracts
# the archive into the Docker volume once (marker: .ravios-model-ready).
# Called from the generic start path so models load without depending on S70
# autostart.

seed_model_archive() {
    json="$1"
    app_dir="$2"

    model_archive="$(sed -n 's/.*"model_archive"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json" | head -1)"
    model_volume="$(sed -n 's/.*"model_volume"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json" | head -1)"

    [ -n "$model_archive" ] && [ -n "$model_volume" ] || return 0

    model_path="$app_dir/$model_archive"
    if [ ! -s "$model_path" ]; then
        # Archive may already have been extracted and removed on a previous boot
        return 0
    fi

    docker volume create "$model_volume" >/dev/null 2>&1 || true
    mp="$(docker volume inspect --format '{{.Mountpoint}}' "$model_volume" 2>/dev/null || true)"
    if [ -z "$mp" ] || [ ! -d "$mp" ]; then
        warn "cannot resolve mountpoint for model volume $model_volume"
        return 0
    fi

    if [ -f "$mp/.ravios-model-ready" ]; then
        return 0
    fi

    log "extracting model archive $model_archive → volume $model_volume"
    if tar -xf "$model_path" -C "$mp"; then
        touch "$mp/.ravios-model-ready"
        rm -f "$model_path"
        log "model seed complete on $model_volume"
    else
        warn "failed to extract $model_path"
        return 1
    fi
    return 0
}


# ---------------------------------------------------------------------------
# Pre-start helpers (declared in manifest – no per-app scripts)
# ---------------------------------------------------------------------------
run_pre_start() {
    json="$1"
    image="$2"

    # Extract volume name for clear_locks (simple key extraction)
    vol="$(tr '\n' ' ' < "$json" | sed -n 's/.*"volume"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    # Only act if clear_locks is present
    if ! grep -q '"clear_locks"' "$json" 2>/dev/null; then
        return 0
    fi
    if [ -z "$vol" ]; then
        return 0
    fi

    paths_body="$(tr '\n' ' ' < "$json" | sed -n 's/.*"paths"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' | head -1)"
    if [ -z "$paths_body" ]; then
        return 0
    fi

    if ! docker volume inspect "$vol" >/dev/null 2>&1; then
        docker volume create "$vol" >/dev/null 2>&1 || true
    fi

    rm_cmd="mkdir -p /data/Downloads; "
    for p in $(echo "$paths_body" | tr ',' '\n' | sed 's/[[:space:]]*"\([^"]*\)".*/\1/'); do
        [ -n "$p" ] || continue
        rm_cmd="${rm_cmd}rm -f /data/$p 2>/dev/null; "
    done
    rm_cmd="${rm_cmd}true"

    log "pre_start: clearing locks on volume $vol"
    docker run --rm \
        -v "$vol:/data" \
        --entrypoint /bin/sh \
        "$image" \
        -c "$rm_cmd" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Security baseline (applied to every container)
# ---------------------------------------------------------------------------
security_baseline_args() {
    echo "--security-opt=no-new-privileges:true"
}


# ---------------------------------------------------------------------------
# Environment variable support
# Supported manifest forms:
#   "environment": {
#     "KEY": "value",
#     "FLAG": true,
#     "COUNT": 3
#   }
#   "env_from_host": [ "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "LANG" ]
#
# Providers may also emit ENV:KEY=VALUE lines.
# ---------------------------------------------------------------------------

# Emit KEY=VALUE lines for every entry in the top-level "environment" object.
# Handles string, boolean and numeric values.
json_environment_pairs() {
    file="$1"
    [ -r "$file" ] || return 1

    # Flatten and extract the environment object body
    body="$(tr '\n' ' ' < "$file" | sed -n 's/.*"environment"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p')"
    [ -n "$body" ] || return 1

    # Split on commas that separate object entries, then parse each pair
    # Works for: "KEY": "value" | "KEY": true | "KEY": false | "KEY": 123
    echo "$body" | tr ',' '\n' | while IFS= read -r pair; do
        k="$(echo "$pair" | sed -n 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/p')"
        [ -n "$k" ] || continue

        # Quoted string value
        v="$(echo "$pair" | sed -n 's/.*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        if [ -n "$v" ]; then
            printf '%s=%s\n' "$k" "$v"
            continue
        fi

        # Bare boolean / number
        v="$(echo "$pair" | sed -n 's/.*:[[:space:]]*\([^[:space:],}]*\).*/\1/p')"
        if [ -n "$v" ]; then
            printf '%s=%s\n' "$k" "$v"
        fi
    done
}

# Emit KEY=VALUE for host variables listed in env_from_host (only if set).
json_env_from_host_pairs() {
    file="$1"
    for hk in $(json_get_array "$file" env_from_host 2>/dev/null || true); do
        [ -n "$hk" ] || continue
        # Indirect expansion; empty values are skipped so containers
        # do not receive blank overrides.
        eval "hv=\${$hk-}"
        if [ -n "$hv" ]; then
            printf '%s=%s\n' "$hk" "$hv"
        fi
    done
}

# Apply all environment sources into docker -e arguments via add_arg callback.
# Caller must define add_arg().
apply_environment() {
    json="$1"
    envtmp="/tmp/ravios-env.$$"
    : > "$envtmp"

    # 1. Static environment from the manifest
    json_environment_pairs "$json" 2>/dev/null >> "$envtmp" || true

    # 2. Selected host environment variables from env_from_host
    json_env_from_host_pairs "$json" 2>/dev/null >> "$envtmp" || true

    # 3. Global host defaults (TZ, LANG) unless already set in the manifest
    #    or already collected above. Manifest values always win.
    for gk in TZ LANG; do
        if grep -q "^${gk}=" "$envtmp" 2>/dev/null; then
            continue
        fi
        eval "gv=\${$gk-}"
        if [ -n "$gv" ]; then
            printf '%s=%s\n' "$gk" "$gv" >> "$envtmp"
        fi
    done

    # 4. Built-in helpers (e.g. webui secret)
    if grep -q '"secret_key"[[:space:]]*:[[:space:]]*true' "$json" 2>/dev/null; then
        sk="$(ensure_secret_key)"
        printf 'WEBUI_SECRET_KEY=%s\n' "$sk" >> "$envtmp"
    fi

    # Apply all collected pairs (same shell – add_arg is visible)
    while IFS= read -r kv; do
        [ -n "$kv" ] || continue
        add_arg "-e"
        add_arg "$kv"
    done < "$envtmp"
    rm -f "$envtmp"
}

# ---------------------------------------------------------------------------
# Secret key helper
# ---------------------------------------------------------------------------
ensure_secret_key() {
    secret_dir="/var/lib/ravios/webui"
    secret_file="$secret_dir/secret_key"
    if [ -s "$secret_file" ]; then
        cat "$secret_file"
        return 0
    fi
    mkdir -p "$secret_dir"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32 > "$secret_file"
    else
        tr -dc 'a-f0-9' < /dev/urandom | head -c 64 > "$secret_file"
    fi
    chmod 600 "$secret_file"
    cat "$secret_file"
}

# ---------------------------------------------------------------------------
# CLI link management
# /usr/bin/<cli_name> -> ravios-app  so the user can type the app name directly.
# ---------------------------------------------------------------------------
ensure_cli_links() {
    # Symlinks are created on the *running Linux appliance* only (never stored
    # in the Windows-side overlay). Safe and simple.
    _link_cli() {
        cli="$1"
        [ -n "$cli" ] || return 0
        link="$CLI_LINK_DIR/$cli"
        if [ -L "$link" ]; then
            target="$(readlink "$link" 2>/dev/null || true)"
            case "$target" in
                ravi|*ravi) return 0 ;;
            esac
        elif [ -e "$link" ]; then
            return 0
        fi
        ln -sf ravi "$link" 2>/dev/null || true
    }

    # Explicit manifests
    if [ -d "$SEED_ROOT" ]; then
        for dir in "$SEED_ROOT"/*; do
            [ -f "$dir/app.json" ] || continue
            cli="$(json_get "$dir/app.json" cli_name 2>/dev/null || true)"
            [ -n "$cli" ] || cli="$(json_get "$dir/app.json" name 2>/dev/null || true)"
            _link_cli "$cli"
        done
    fi

    # Local images without a materialised manifest → still get a CLI name
    # so the user can type the name directly; runtime uses the live template.
    if docker_ready; then
        docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null |             grep -v ':<none>$' | grep -v '^<none>' | while IFS= read -r img; do
            [ -n "$img" ] || continue
            cli="$(sanitize_cli_name "$img")"
            _link_cli "$cli"
        done
    fi
}
