#!/usr/bin/env bash
# instance.sh — container lifecycle. Version is the identity (DESIGN.md D1) and
# Docker labels are the only state (DESIGN.md D2).

# --------------------------------------------------------------- inspection --

# instance_state <version> -> running | stopped | absent
instance_state() {
    local st
    st=$(docker inspect -f '{{.State.Status}}' "$(container_name "$1")" 2>/dev/null) || {
        printf 'absent'; return 0; }
    case "$st" in running) printf 'running' ;; *) printf 'stopped' ;; esac
}

volume_exists() { docker volume inspect "$(volume_name "$1")" >/dev/null 2>&1; }

# volume_recorded_version <version> — the DSS version that last wrote this
# datadir, from its label. Empty if unlabelled (manually created).
volume_recorded_version() {
    docker volume inspect -f "{{index .Labels \"$LABEL_PREFIX.version\"}}" \
        "$(volume_name "$1")" 2>/dev/null | grep -v '^<no value>$' || true
}

# container_recorded_port <version> — the port actually published, from the
# label. This, never the formula, is the source of truth (DESIGN.md D1).
container_recorded_port() {
    docker inspect -f "{{index .Config.Labels \"$LABEL_PREFIX.port\"}}" \
        "$(container_name "$1")" 2>/dev/null | grep -v '^<no value>$' || true
}

port_in_use() {
    if command -v nc >/dev/null 2>&1; then nc -z 127.0.0.1 "$1" >/dev/null 2>&1; else
        (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; fi
}

# resolve_host_port <version> — the formula, unless it is taken by something
# that is not us, in which case walk upward. The result is recorded on the label.
resolve_host_port() {
    local v="$1" p existing
    existing=$(container_recorded_port "$v")
    if [ -n "$existing" ]; then printf '%s' "$existing"; return 0; fi
    p=$(version_port "$v")
    local tries=0
    while port_in_use "$p" && [ "$tries" -lt 50 ]; do
        log_warn "port $p is in use; trying $((p + 1))" >&2
        p=$((p + 1)); tries=$((tries + 1))
    done
    printf '%s' "$p"
}

# ------------------------------------------------------------------- images --

image_ref() {
    if [ "$(catalog_source "$1")" = "pull" ]; then image_hub "$1"; else image_local "$1"; fi
}

image_present() { docker image inspect "$1" >/dev/null 2>&1; }

# image_ensure <version> — pull from Hub, or build from the installer kit.
image_ensure() {
    local v="$1" ref src
    ref=$(image_ref "$v"); src=$(catalog_source "$v")
    if image_present "$ref"; then log_dim "image present: $ref"; return 0; fi

    if [ "$src" = "pull" ]; then
        log_step "pulling $ref (not gated: first pull is several GB)"
        # shellcheck disable=SC2046
        docker pull $(docker_platform_args) "$ref" || die "pull failed: $ref"
    else
        image_build "$v"
    fi
}

# ---------------------------------------------------------------- readiness --

# Readiness is measured against the BACKEND, not nginx.
#
# nginx starts and serves the login page well before the DSS backend is
# listening: measured on a 12.6.7 container, `GET /` returned 200 at t=50s while
# the API still returned 502, and the backend only answered at t=60s. Anything
# that talks to DSS in that window fails — `dsscli set-license` is a REST client
# against the backend on :10001, not a filesystem operation, and it fails with
# "connection refused". So probing `/` is a false positive.
#
# An API path proxied to the backend distinguishes them: 502/503/504 means nginx
# is up but the backend is not; 401 means the backend answered and demanded
# credentials, which is exactly the readiness signal we want.
DSS_READY_PATH="/public/api/admin/licensing/status"

# instance_wait <version> [timeout_seconds]
instance_wait() {
    local v="$1" timeout="${2:-1800}" port code waited=0 interval=5 saw_nginx=0
    port=$(container_recorded_port "$v"); [ -n "$port" ] || port=$(version_port "$v")

    log_step "waiting for the DSS backend on port $port (timeout ${timeout}s)"
    while [ "$waited" -lt "$timeout" ]; do
        if [ "$(instance_state "$v")" != "running" ]; then
            log_error "container stopped while starting up"
            log_dim "last log lines:"
            docker logs --tail 20 "$(container_name "$v")" 2>&1 | sed 's/^/    /' >&2
            return 1
        fi
        code=$(curl -sS -o /dev/null -m 5 -w '%{http_code}' \
                "http://localhost:$port$DSS_READY_PATH" 2>/dev/null || printf '000')
        case "$code" in
            200|401|403)
                log_ok "DSS backend is ready (HTTP $code) after ${waited}s"; return 0 ;;
            502|503|504)
                if [ "$saw_nginx" -eq 0 ]; then
                    saw_nginx=1
                    log_dim "nginx is up; waiting for the backend (this is the slow part)"
                fi ;;
        esac
        sleep "$interval"; waited=$((waited + interval))
        if [ $((waited % 60)) -eq 0 ]; then log_dim "still waiting… ${waited}s (HTTP $code)"; fi
    done
    log_error "timed out after ${timeout}s waiting for the DSS backend on port $port"
    log_dim "nginx may be serving the login page while the backend is still starting"
    return 1
}

# ----------------------------------------------------------------- the guard --

# instance_guard_datadir <version> <allow_migrate>
# run.sh silently migrates a datadir whose version differs, and there is no
# downgrade (RESEARCH §7). This is the single most destructive thing the tool
# can do, so it is the one place the no-prompt rule yields (KNOWN_ISSUES K3).
instance_guard_datadir() {
    local v="$1" allow="$2" recorded
    volume_exists "$v" || return 0
    recorded=$(volume_recorded_version "$v")

    if [ -z "$recorded" ]; then
        log_warn "volume $(volume_name "$v") has no version label (created outside dss-lab)"
        log_dim "proceeding; DSS will migrate it in place if its version differs"
        return 0
    fi
    [ "$recorded" = "$v" ] && return 0

    if [ "$allow" = "1" ]; then
        log_warn "migrating datadir from DSS $recorded to $v — this is IRREVERSIBLE"
        return 0
    fi
    log_error "datadir $(volume_name "$v") was written by DSS $recorded, not $v"
    log_dim "starting $v against it would migrate it in place, irreversibly, with no downgrade"
    log_dim "pass --migrate to accept that, or use a different version"
    return 1
}

# ---------------------------------------------------------------------- up --

# instance_up <version> [--migrate] [--no-wait] [--timeout N]
instance_up() {
    local v="$1"; shift
    local migrate=0 wait=1 timeout=1800
    while [ $# -gt 0 ]; do
        case "$1" in
            --migrate) migrate=1; shift ;;
            --no-wait) wait=0; shift ;;
            --timeout) timeout="$2"; shift 2 ;;
            *) die "up: unknown option $1" ;;
        esac
    done

    local state; state=$(instance_state "$v")

    case "$state" in
        running)
            log_ok "DSS $v is already running"
            return 0 ;;
        stopped)
            instance_guard_datadir "$v" "$migrate" || return 1
            log_step "starting existing container $(container_name "$v")"
            docker start "$(container_name "$v")" >/dev/null || die "failed to start container"
            [ "$wait" -eq 1 ] && { instance_wait "$v" "$timeout" || return 1; }
            return 0 ;;
    esac

    # absent -> create
    instance_guard_datadir "$v" "$migrate" || return 1
    image_ensure "$v"

    local port vol; port=$(resolve_host_port "$v"); vol=$(volume_name "$v")

    if ! volume_exists "$v"; then
        # shellcheck disable=SC2046
        docker volume create --label "$LABEL_PREFIX.managed=true" \
            --label "$LABEL_PREFIX.version=$v" "$vol" >/dev/null
        log_dim "created volume $vol"
    fi

    local mem_args="" vm_mem
    vm_mem=$(vm_setting MemoryMiB || printf '')
    if [ -n "$vm_mem" ] && [ "$vm_mem" -gt 2048 ]; then
        mem_args="--memory $(( vm_mem - 1024 ))m"
        log_dim "container memory limit: $(( vm_mem - 1024 ))m (VM has ${vm_mem}m)"
    fi

    log_step "creating $(container_name "$v") on port $port"
    # shellcheck disable=SC2046,SC2086
    docker run -d \
        --name "$(container_name "$v")" \
        $(docker_platform_args) \
        -p "$port:$DSS_CONTAINER_PORT" \
        -v "$vol:$DSS_DATADIR" \
        $mem_args \
        --label "$LABEL_PREFIX.managed=true" \
        --label "$LABEL_PREFIX.version=$v" \
        --label "$LABEL_PREFIX.port=$port" \
        --label "$LABEL_PREFIX.source=$(catalog_source "$v")" \
        --label "$LABEL_PREFIX.era=$(version_era "$v")" \
        "$(image_ref "$v")" >/dev/null || die "failed to create container"

    log_dim "first boot runs installer.sh + R integration under emulation; this is slow"
    [ "$wait" -eq 1 ] && { instance_wait "$v" "$timeout" || return 1; }
    return 0
}

# ------------------------------------------------------------ other verbs --

instance_ls() {
    local rows
    rows=$(docker ps -a --filter "label=$LABEL_PREFIX.managed=true" \
        --format "{{.Label \"$LABEL_PREFIX.version\"}}|{{.Names}}|{{.State}}|{{.Label \"$LABEL_PREFIX.port\"}}|{{.Label \"$LABEL_PREFIX.source\"}}" 2>/dev/null)
    if [ -z "$rows" ]; then log_info "no dss-lab containers"; return 0; fi
    printf '%-9s  %-13s  %-9s  %-6s  %-6s  %s\n' VERSION CONTAINER STATE PORT SOURCE URL
    # sort -V is not dependable on macOS; build a zero-padded key, sort, strip it
    printf '%s\n' "$rows" \
        | awk -F'|' '{n=split($1,p,"."); printf "%03d%03d%03d|%s\n", p[1],p[2],p[3], $0}' \
        | sort | cut -d'|' -f2- \
        | while IFS='|' read -r ver name state port src; do
        printf '%-9s  %-13s  %-9s  %-6s  %-6s  http://localhost:%s\n' \
            "$ver" "$name" "$state" "$port" "$src" "$port"
    done
}

instance_stop()  { docker stop "$(container_name "$1")" >/dev/null && log_ok "stopped DSS $1"; }
instance_logs()  { local v="$1"; shift; docker logs "$@" "$(container_name "$v")"; }
instance_shell() { docker exec -it "$(container_name "$1")" /bin/bash; }

instance_url() {
    local p; p=$(container_recorded_port "$1"); [ -n "$p" ] || p=$(version_port "$1")
    printf 'http://localhost:%s\n' "$p"
}

# instance_rm <version> [--keep-volume]
instance_rm() {
    local v="$1" keep=0
    [ "${2:-}" = "--keep-volume" ] && keep=1
    docker rm -f "$(container_name "$v")" >/dev/null 2>&1 && log_ok "removed container $(container_name "$v")" \
        || log_dim "no container $(container_name "$v")"
    if [ "$keep" -eq 1 ]; then
        log_dim "kept volume $(volume_name "$v")"
    elif volume_exists "$v"; then
        docker volume rm "$(volume_name "$v")" >/dev/null && log_ok "removed volume $(volume_name "$v")"
    fi
}

instance_gc() {
    log_step "reclaimable space before:"
    docker system df --format '  {{.Type}}: {{.Size}} (reclaimable {{.Reclaimable}})'
    log_step "removing dangling images and build cache"
    docker image prune -f >/dev/null 2>&1 || true
    docker builder prune -f >/dev/null 2>&1 || true
    log_step "orphaned dss-lab volumes (no matching container)"
    docker volume ls --filter "label=$LABEL_PREFIX.managed=true" --format '{{.Name}}' | while read -r vol; do
        local ver="${vol#dss-}"; ver="${ver%-data}"
        if [ "$(instance_state "$ver")" = "absent" ]; then
            log_warn "orphan: $vol (DSS $ver) — remove with: dss-lab rm $ver"
        fi
    done
    log_step "reclaimable space after:"
    docker system df --format '  {{.Type}}: {{.Size}} (reclaimable {{.Reclaimable}})'
}
