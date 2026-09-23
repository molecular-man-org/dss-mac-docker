#!/usr/bin/env bash
# snapshot.sh — datadir snapshots, restore, and guarded upgrades (DESIGN.md D5).
#
# A snapshot is a labelled copy of a datadir volume. The copy is made by the
# version's own DSS image (already required for the instance, so no extra image
# is pulled), run as root with `cp -a` to preserve ownership and modes.
#
# Snapshot volumes carry `snapshot=true` and NOT `managed=true`, so `ls` and
# `gc` — which treat managed volumes as instances — never mistake one for a node.

SNAP_INFIX="snap"

# snapshot_name_valid <name> — a Docker-volume-safe token
snapshot_name_valid() {
    printf '%s' "$1" | grep -qE '^[A-Za-z0-9][A-Za-z0-9_.-]{0,40}$'
}

# snapshot_volume <version> <name> -> dss-<version>-snap-<name>
snapshot_volume() { printf 'dss-%s-%s-%s' "$1" "$SNAP_INFIX" "$2"; }

# volume_clone <src_volume> <dst_volume> <image> [wipe]
# Copies the whole datadir, preserving ownership. With `wipe`, the destination is
# emptied first (restore); otherwise it must already be empty (fresh volume).
volume_clone() {
    local src="$1" dst="$2" image="$3" wipe="${4:-}" script
    script='cp -a /from/. /to/'
    [ "$wipe" = "wipe" ] && script='find /to -mindepth 1 -delete && cp -a /from/. /to/'
    # shellcheck disable=SC2046
    docker run --rm -u root $(docker_platform_args) \
        --entrypoint /bin/bash \
        -v "$src:/from:ro" -v "$dst:/to" \
        "$image" -c "$script" >/dev/null
}

# _snap_label <volume> <label> — a label value, empty when unset
_snap_label() {
    docker volume inspect -f "{{index .Labels \"$LABEL_PREFIX.$2\"}}" "$1" 2>/dev/null \
        | grep -v '^<no value>$' || true
}

# _quiesce <version> — stop a running instance so the copy is consistent.
# Prints "running" when it had to stop one, so the caller can restart it.
_quiesce() {
    if [ "$(instance_state "$1")" = "running" ]; then
        log_step "stopping DSS $1 for a consistent copy"
        instance_stop "$1" >&2 || return 1
        printf 'running'
    fi
}

# _image_for_copy <version> — the version's own image, ensured present
_image_for_copy() {
    local ref; ref=$(image_ref "$1")
    image_present "$ref" || image_ensure "$1"
    printf '%s' "$ref"
}

# snapshot_create <version> [name]
snapshot_create() {
    local v="$1" name="${2:-$(date +%Y%m%d-%H%M%S)}"
    snapshot_name_valid "$name" || die "snapshot: invalid name '$name' (letters, digits, . _ -)"
    volume_exists "$v" || die "snapshot: no datadir for DSS $v (dss-lab up $v first)"
    local snap; snap=$(snapshot_volume "$v" "$name")
    docker volume inspect "$snap" >/dev/null 2>&1 \
        && die "snapshot: '$name' already exists for DSS $v (dss-lab snapshot rm $v $name)"

    local was; was=$(_quiesce "$v") || die "snapshot: could not stop DSS $v"
    log_step "copying $(volume_name "$v") -> $snap"
    docker volume create \
        --label "$LABEL_PREFIX.snapshot=true" \
        --label "$LABEL_PREFIX.version=$v" \
        --label "$LABEL_PREFIX.snapshot_name=$name" \
        --label "$LABEL_PREFIX.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$snap" >/dev/null
    if ! volume_clone "$(volume_name "$v")" "$snap" "$(_image_for_copy "$v")"; then
        docker volume rm "$snap" >/dev/null 2>&1 || true
        die "snapshot: copy failed; partial snapshot removed"
    fi
    log_ok "snapshot '$name' of DSS $v"
    if [ "$was" = "running" ]; then
        log_step "restarting DSS $v"
        instance_up "$v" || return 1
    fi
    printf '%s\n' "$name"
}

# snapshot_ls [version] — name, version, created, tab-free columns
snapshot_ls() {
    local rows
    rows=$(docker volume ls --filter "label=$LABEL_PREFIX.snapshot=true" --format \
        "{{.Label \"$LABEL_PREFIX.version\"}}|{{.Label \"$LABEL_PREFIX.snapshot_name\"}}|{{.Label \"$LABEL_PREFIX.created\"}}" 2>/dev/null)
    [ -n "${1:-}" ] && rows=$(printf '%s\n' "$rows" | awk -F'|' -v v="$1" '$1==v')
    if [ -z "$rows" ]; then log_info "no snapshots"; return 0; fi
    printf '%-9s  %-24s  %s\n' VERSION NAME CREATED
    printf '%s\n' "$rows" | sort | awk -F'|' '{printf "%-9s  %-24s  %s\n", $1, $2, $3}'
}

# snapshot_rm <version> <name>
snapshot_rm() {
    local snap; snap=$(snapshot_volume "$1" "$2")
    docker volume inspect "$snap" >/dev/null 2>&1 || die "snapshot: no '$2' snapshot of DSS $1"
    [ "$(_snap_label "$snap" snapshot)" = "true" ] || die "snapshot: $snap is not a dss-lab snapshot"
    docker volume rm "$snap" >/dev/null && log_ok "removed snapshot '$2' of DSS $1"
}

# snapshot_restore <version> <name> --force
# Replaces the live datadir with the snapshot. Destructive to the current
# contents, so it needs --force rather than a prompt (nothing here prompts).
snapshot_restore() {
    local v="$1" name="$2" force="${3:-}"
    if [ "$force" != "--force" ]; then
        log_error "restore replaces the current datadir of DSS $v with snapshot '$name'"
        log_dim "the current contents are lost; pass --force to accept that"
        return 1
    fi
    local snap; snap=$(snapshot_volume "$v" "$name")
    docker volume inspect "$snap" >/dev/null 2>&1 || die "restore: no '$name' snapshot of DSS $v"
    [ "$(_snap_label "$snap" snapshot)" = "true" ] || die "restore: $snap is not a dss-lab snapshot"
    [ "$(_snap_label "$snap" version)" = "$v" ] \
        || die "restore: snapshot was taken from DSS $(_snap_label "$snap" version), not $v"
    volume_exists "$v" || die "restore: no datadir for DSS $v to restore into"

    local was; was=$(_quiesce "$v") || die "restore: could not stop DSS $v"
    log_step "restoring $snap -> $(volume_name "$v")"
    volume_clone "$snap" "$(volume_name "$v")" "$(_image_for_copy "$v")" wipe \
        || die "restore: copy failed — the datadir of DSS $v may be incomplete; restore again"
    log_ok "restored DSS $v from snapshot '$name'"
    if [ "$was" = "running" ]; then
        log_step "restarting DSS $v"
        instance_up "$v" || return 1
    fi
}

# upgrade_check <from> <to> — every refusal, in one place, so it is testable
# without Docker. Prints the reason and returns 1 on refusal.
upgrade_check() {
    local from="$1" to="$2"
    if [ "$from" = "$to" ]; then
        log_error "upgrade: $from and $to are the same version"; return 1
    fi
    if ! version_gt "$to" "$from"; then
        log_error "upgrade: $to is older than $from — DSS has no downgrade path (RESEARCH §7)"
        return 1
    fi
    return 0
}

# instance_upgrade <from> <to> [--no-wait] [--timeout N]
#
# Clones the datadir of <from> into a fresh volume for <to> and starts <to>
# against it, letting DSS's own run.sh perform the migration. <from> is left
# stopped and untouched, so it IS the rollback: nothing here can lose its data.
#
# The new volume is labelled with the TARGET version (plus `migrated_from`),
# because Docker volume labels are immutable — labelling it with the source
# version would make the datadir guard refuse every later `up`. This command is
# the explicit acceptance of the migration that the guard otherwise demands.
instance_upgrade() {
    local from="$1" to="$2"; shift 2
    local wait_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-wait) wait_args+=(--no-wait); shift ;;
            --timeout) wait_args+=(--timeout "$2"); shift 2 ;;
            *) die "upgrade: unknown option $1" ;;
        esac
    done
    upgrade_check "$from" "$to" || return 1
    volume_exists "$from" || die "upgrade: no datadir for DSS $from (dss-lab up $from first)"
    if [ "$(instance_state "$to")" != "absent" ] || volume_exists "$to"; then
        log_error "upgrade: DSS $to already has a container or datadir"
        log_dim "upgrade creates $to from $from and will not overwrite existing data"
        log_dim "remove it first with: dss-lab rm $to"
        return 1
    fi
    local recorded; recorded=$(volume_recorded_version "$from")
    if [ -n "$recorded" ] && [ "$recorded" != "$from" ]; then
        die "upgrade: datadir of $from was written by $recorded — refusing an ambiguous source"
    fi

    local was; was=$(_quiesce "$from") || die "upgrade: could not stop DSS $from"
    [ "$was" = "running" ] || log_dim "DSS $from is stopped; cloning its datadir"

    image_ensure "$to"
    local newvol; newvol=$(volume_name "$to")
    log_step "cloning $(volume_name "$from") -> $newvol"
    docker volume create \
        --label "$LABEL_PREFIX.managed=true" \
        --label "$LABEL_PREFIX.version=$to" \
        --label "$LABEL_PREFIX.migrated_from=$from" \
        "$newvol" >/dev/null
    if ! volume_clone "$(volume_name "$from")" "$newvol" "$(_image_for_copy "$to")"; then
        docker volume rm "$newvol" >/dev/null 2>&1 || true
        die "upgrade: clone failed; partial datadir removed, DSS $from untouched"
    fi
    log_warn "starting DSS $to against a clone of the $from datadir — DSS will migrate it"
    log_dim "DSS $from is untouched and stopped; it is your rollback"
    instance_up "$to" "${wait_args[@]+"${wait_args[@]}"}" || return 1
    log_ok "upgraded $from -> $to"
    log_dim "next: dss-lab provision $to   (registers the new node and mints its API key)"
}
