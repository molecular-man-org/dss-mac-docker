#!/usr/bin/env bash
# bundle.sh — preload a project export into a running instance (ROADMAP phase 6).
#
# "Bundle" here means a DSS project export archive (.zip), the format
# `dsscli project-export` and the UI's Export button produce. Importing one is
# how a provisioned instance gets real content without writing to it through the
# API; see docs/SEEDING.md.

BUNDLE_TMP="/tmp/dss-lab-bundle.zip"

# bundle_validate <file> — a readable ZIP that looks like a DSS project export:
# it carries export-manifest.json or project_config/params.json, which every real
# export has (a project.json at the root is NOT a marker; there is none).
# Prints the reason and returns 1 otherwise.
bundle_validate() {
    local f="$1"
    [ -f "$f" ] || { log_error "bundle: no such file: $f"; return 1; }
    python3 - "$f" <<'PYEOF' || return 1
import sys, zipfile
try:
    names = zipfile.ZipFile(sys.argv[1]).namelist()
except Exception as e:
    sys.exit("✗ bundle: not a readable ZIP archive (%s)" % e)
if "export-manifest.json" not in names and "project_config/params.json" not in names:
    sys.exit("✗ bundle: no export-manifest.json or project_config/params.json — not a DSS project export")
PYEOF
}

# bundle_remap_valid <OLD=NEW> — a non-empty name on each side of one '='
bundle_remap_valid() {
    case "$1" in
        *=*=*|=*|*=) return 1 ;;
        *=*) return 0 ;;
        *) return 1 ;;
    esac
}

# bundle_import <version> <file> [--project-key KEY] [--remap-connection OLD=NEW]...
bundle_import() {
    local v="$1" file="$2"; shift 2
    local import_args=() key=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --project-key)
                [ -n "${2:-}" ] || die "bundle: --project-key needs a value"
                key="$2"; import_args+=(--project-key "$2"); shift 2 ;;
            --remap-connection)
                bundle_remap_valid "${2:-}" \
                    || die "bundle: --remap-connection needs OLD=NEW, got '${2:-}'"
                import_args+=(--remap-connection "$2"); shift 2 ;;
            *) die "bundle: unknown option $1" ;;
        esac
    done
    bundle_validate "$file" || return 1
    [ "$(instance_state "$v")" = "running" ] || die "DSS $v is not running (dss-lab up $v)"

    local c rc=0; c=$(container_name "$v")
    log_step "importing $(basename "$file") into DSS $v${key:+ as $key}"
    docker cp "$file" "$c:$BUNDLE_TMP" >/dev/null || die "bundle: could not copy the archive into $c"
    docker exec "$c" "$DSS_DATADIR/bin/dsscli" project-import \
        ${import_args[@]+"${import_args[@]}"} "$BUNDLE_TMP" || rc=$?
    # `|| rc=$?`, not a bare call: dss-lab runs under `set -e`, and a bare failing
    # call would abort here, skipping the cleanup and the message below.
    # Root-owned copy, so remove it as root — and on failure too.
    docker exec -u root "$c" rm -f "$BUNDLE_TMP" >/dev/null 2>&1 || true
    if [ "$rc" -ne 0 ]; then
        log_error "DSS $v rejected the import (dsscli exit $rc)"
        log_dim "usual causes: the project key already exists here, or the archive comes from a newer DSS"
        return "$rc"
    fi
    log_ok "imported into DSS $v"
}
