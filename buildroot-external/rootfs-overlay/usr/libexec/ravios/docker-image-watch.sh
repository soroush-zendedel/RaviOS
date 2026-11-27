#!/bin/sh
# Watch Docker image events and run: ravi refresh
#
# Fires after: pull, load, import, tag (new local name).
# Debounced so a multi-layer pull only triggers one refresh.

set -eu

RAVI_BIN="${RAVI_BIN:-/usr/bin/ravi}"
DEBOUNCE_SEC="${RAVI_REFRESH_DEBOUNCE:-3}"
LOG_TAG="ravi-image-watch"

log() { echo "$LOG_TAG: $*" >&2; }

wait_for_docker() {
    i=0
    while [ "$i" -lt 60 ]; do
        if docker info >/dev/null 2>&1; then
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    return 1
}

run_refresh() {
    if [ -x "$RAVI_BIN" ]; then
        log "running ravi refresh"
        "$RAVI_BIN" refresh >/dev/null 2>&1 || \
            "$RAVI_BIN" refresh 2>&1 | while IFS= read -r line; do log "$line"; done || true
    else
        log "ravi not found at $RAVI_BIN"
    fi
}

# Debounce: coalesce bursts of events into one refresh
schedule_refresh() {
    # Kill previous pending sleep/refresh chain for this watcher
    if [ -n "${_pending_pid:-}" ] && kill -0 "$_pending_pid" 2>/dev/null; then
        kill "$_pending_pid" 2>/dev/null || true
    fi
    (
        sleep "$DEBOUNCE_SEC"
        run_refresh
    ) &
    _pending_pid=$!
}

main() {
    wait_for_docker || {
        log "Docker not ready, exiting"
        exit 1
    }

    log "watching image pull/load/import/tag events"

    # --filter can be repeated. Format prints action only.
    docker events \
        --filter 'type=image' \
        --filter 'event=pull' \
        --filter 'event=load' \
        --filter 'event=import' \
        --filter 'event=tag' \
        --format '{{.Action}}' \
    | while IFS= read -r action; do
        [ -n "$action" ] || continue
        log "event: $action"
        schedule_refresh
    done
}

main "$@"
