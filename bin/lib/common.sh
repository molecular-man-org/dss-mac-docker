#!/usr/bin/env bash
# common.sh — shared helpers for dss-lab.
#
# Written for bash 3.2 (the macOS system bash): no associative arrays, no
# ${var,,}. Sourced by bin/dss-lab; not executable on its own.

# Constants and paths below are consumed by the other sourced libraries. Those
# are linted in isolation, so SC2034 reports them as unused here.
# shellcheck disable=SC2034

# ---------------------------------------------------------------- constants --

LABEL_PREFIX="dss-mac-docker"
DSS_PLATFORM="linux/amd64"     # DSS ships x86-64 only; see RESEARCH.md §2
DSS_CONTAINER_PORT=10000       # in-container port; see RESEARCH.md §7
DSS_DATADIR="/home/dataiku/dss"
MIN_MAJOR=11                   # supported floor; see HANDOFF.md
DOCKER_SETTINGS="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

# Recommended Docker VM memory, MiB. 6400 is the observed default and is the
# binding constraint on running several versions at once (KNOWN_ISSUES K1).
VM_MEM_WARN=8192
VM_MEM_GOOD=10240

# ------------------------------------------------------------------ logging --

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_DIM=""
fi

log_info()  { printf '%s\n' "$*" >&2; }
log_ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
log_warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_step()  { printf '%s→%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
log_dim()   { printf '%s  %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

die() { log_error "$*"; exit 1; }

# ------------------------------------------------------------------ version --

# version_valid <version> — strict x.y.z
version_valid() {
    case "$1" in
        *[!0-9.]*) return 1 ;;
    esac
    printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
}

version_major() { printf '%s' "${1%%.*}"; }
version_minor() { local r="${1#*.}"; printf '%s' "${r%%.*}"; }
version_patch() { printf '%s' "${1##*.}"; }

# version_in_range <version> — DSS 11.0.0 and later only
version_in_range() {
    version_valid "$1" || return 1
    [ "$(version_major "$1")" -ge "$MIN_MAJOR" ]
}

# version_port <version> — deterministic host port.
#   10000 + (major-11)*1000 + minor*100 + patch*10
# Verified collision-free across all 109 in-range versions (RESEARCH.md §9).
version_port() {
    local v="$1" ma mi pa
    version_valid "$v" || { log_error "not a version: $v"; return 1; }
    ma=$(version_major "$v"); mi=$(version_minor "$v"); pa=$(version_patch "$v")
    printf '%s' $(( 10000 + (ma - MIN_MAJOR) * 1000 + mi * 100 + pa * 10 ))
}

# version_port_is_canonical <version>
# The formula stays injective only while minor and patch are <= 9. Observed
# maxima are 7, but guard rather than assume: a non-canonical version may
# collide, and `up` must fall back to the next free port and record it on the
# container label (DESIGN.md D1).
version_port_is_canonical() {
    local v="$1"
    [ "$(version_minor "$v")" -le 9 ] && [ "$(version_patch "$v")" -le 9 ]
}

# version_era <version> — release era, which fixes base OS and toolchain.
# Boundaries confirmed twice over: Dataiku's Dockerfile commit history and the
# container-image filename suffixes (RESEARCH.md §6).
version_era() {
    local ma
    version_valid "$1" || { log_error "not a version: $1"; return 1; }
    ma=$(version_major "$1")
    if   [ "$ma" -ge 14 ]; then printf 'dss14-15'
    elif [ "$ma" -eq 13 ]; then printf 'dss13'
    elif [ "$ma" -ge 11 ]; then printf 'dss11-12'
    else log_error "unsupported major version: $ma (minimum $MIN_MAJOR)"; return 1
    fi
}

# era_base_image <era> — nearest published Hub image in the same era, reused as
# the build base so the emulated R compile is skipped entirely (DESIGN.md D3).
era_base_image() {
    case "$1" in
        dss11-12) printf 'dataiku/dss:12.6.4' ;;
        dss13)    printf 'dataiku/dss:13.4.4' ;;
        dss14-15) printf 'dataiku/dss:15.0.0' ;;
        *) log_error "unknown era: $1"; return 1 ;;
    esac
}

# --------------------------------------------------------------- identities --
# Version is the identity; every name derives from it (DESIGN.md D1).

container_name() { printf 'dss-%s' "$1"; }
volume_name()    { printf 'dss-%s-data' "$1"; }
image_hub()      { printf 'dataiku/dss:%s' "$1"; }
image_local()    { printf '%s/dss:%s' "$LABEL_PREFIX" "$1"; }
instance_url()   { printf 'http://localhost:%s' "$(version_port "$1")"; }

# ------------------------------------------------------------------- docker --
# --platform belongs only on commands that create or fetch an image. Applying it
# blanket-wise breaks ps/logs/inspect, so it is explicit rather than wrapped.

docker_platform_args() { printf '%s' "--platform $DSS_PLATFORM"; }

docker_present() { command -v docker >/dev/null 2>&1; }

docker_running() { docker info >/dev/null 2>&1; }

require_docker() {
    docker_present || die "docker not found in PATH (expected /usr/local/bin/docker)"
    docker_running || {
        log_error "Docker daemon is not running."
        log_dim "start it with:  open -a Docker"
        exit 1
    }
}

# label_args <version> <source> — labels are the only state (DESIGN.md D2)
label_args() {
    local v="$1" src="$2" era port
    era=$(version_era "$v"); port=$(version_port "$v")
    printf -- '--label %s.managed=true --label %s.version=%s --label %s.port=%s --label %s.source=%s --label %s.era=%s' \
        "$LABEL_PREFIX" "$LABEL_PREFIX" "$v" "$LABEL_PREFIX" "$port" \
        "$LABEL_PREFIX" "$src" "$LABEL_PREFIX" "$era"
}

# ---------------------------------------------------------------- vm probing --

# vm_setting <Key> — read an integer/bool from Docker Desktop's settings store.
vm_setting() {
    [ -f "$DOCKER_SETTINGS" ] || return 1
    python3 -c "
import json,sys
try:
    with open(sys.argv[1]) as f: d=json.load(f)
except Exception: sys.exit(1)
v=d.get(sys.argv[2])
if v is None: sys.exit(1)
print(json.dumps(v) if isinstance(v,bool) else v)
" "$DOCKER_SETTINGS" "$1" 2>/dev/null
}

host_arch() { uname -m; }

# ------------------------------------------------------------------- paths --

# Resolve the repo root from this file's location, following symlinks so the
# skills can be symlinked into ~/.claude/skills and still find the CLI (K6).
resolve_root() {
    local src="${BASH_SOURCE[0]}" dir
    while [ -h "$src" ]; do
        dir=$(cd -P "$(dirname "$src")" && pwd)
        src=$(readlink "$src")
        case "$src" in /*) ;; *) src="$dir/$src" ;; esac
    done
    cd -P "$(dirname "$src")/../.." && pwd
}

DSS_LAB_ROOT="${DSS_LAB_ROOT:-$(resolve_root)}"
DATA_DIR="$DSS_LAB_ROOT/data"
CACHE_DIR="$DSS_LAB_ROOT/.cache"
VERSIONS_FILE="$DATA_DIR/versions-11plus.txt"
HUB_TAGS_FILE="$DATA_DIR/hub-tags-11plus.txt"
