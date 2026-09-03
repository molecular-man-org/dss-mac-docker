#!/usr/bin/env bash
# doctor.sh — preflight checks.
#
# Exit status: 0 all clear, 1 warnings only, 2 something is blocking.

DOCTOR_WARN=0
DOCTOR_FAIL=0

_ck_ok()   { log_ok   "$1"; [ -n "${2:-}" ] && log_dim "$2"; return 0; }
_ck_warn() { log_warn "$1"; [ -n "${2:-}" ] && log_dim "$2"; DOCTOR_WARN=$((DOCTOR_WARN+1)); return 0; }
_ck_fail() { log_error "$1"; [ -n "${2:-}" ] && log_dim "$2"; DOCTOR_FAIL=$((DOCTOR_FAIL+1)); return 0; }

doctor_run() {
    local deep=0
    [ "${1:-}" = "--deep" ] && deep=1

    log_info "dss-mac-docker doctor"
    log_info ""

    # -- host -------------------------------------------------------------
    local arch; arch=$(host_arch)
    if [ "$arch" = "arm64" ]; then
        _ck_ok "host architecture: arm64" \
            "DSS is x86-64 only, so containers run emulated (RESEARCH §2)"
    else
        _ck_ok "host architecture: $arch" "native x86-64; no emulation needed"
    fi

    # -- docker cli / daemon ----------------------------------------------
    if ! docker_present; then
        _ck_fail "docker CLI not found" "expected /usr/local/bin/docker from Docker Desktop"
        doctor_report; return $?
    fi
    _ck_ok "docker CLI: $(docker --version 2>/dev/null | head -1)"

    local daemon_up=0
    if docker_running; then
        daemon_up=1
        _ck_ok "docker daemon: running"
    else
        _ck_fail "docker daemon: not running" "start it with:  open -a Docker"
    fi

    # -- rosetta ----------------------------------------------------------
    if [ "$arch" = "arm64" ]; then
        local rosetta; rosetta=$(vm_setting UseVirtualizationFrameworkRosetta || printf 'unknown')
        case "$rosetta" in
            true)  _ck_ok "Rosetta emulation: enabled" ;;
            false) _ck_fail "Rosetta emulation: disabled" \
                     "enable it in Docker Desktop > Settings > General, or amd64 images will not run" ;;
            *)     _ck_warn "Rosetta emulation: could not read setting" \
                     "checked $DOCKER_SETTINGS" ;;
        esac
    fi

    # -- vm memory --------------------------------------------------------
    local mem; mem=$(vm_setting MemoryMiB || printf '')
    if [ -n "$mem" ]; then
        if [ "$mem" -ge "$VM_MEM_GOOD" ]; then
            _ck_ok "Docker VM memory: ${mem} MiB"
        elif [ "$mem" -ge "$VM_MEM_WARN" ]; then
            _ck_warn "Docker VM memory: ${mem} MiB" \
                "workable for one instance; ${VM_MEM_GOOD} MiB recommended"
        else
            _ck_warn "Docker VM memory: ${mem} MiB — below recommended" \
                "raise to ~${VM_MEM_GOOD} MiB in Docker Desktop > Settings > Resources (needs a restart). Expect one modern DSS instance at a time (K1)"
        fi
    else
        _ck_warn "Docker VM memory: could not read setting"
    fi

    # -- vm cpus ----------------------------------------------------------
    local cpus; cpus=$(vm_setting Cpus || printf '')
    [ -n "$cpus" ] && _ck_ok "Docker VM CPUs: $cpus"

    # -- disk -------------------------------------------------------------
    local disk; disk=$(vm_setting DiskSizeMiB || printf '')
    if [ "$daemon_up" -eq 1 ]; then
        local reclaim
        reclaim=$(docker system df --format '{{.Type}} {{.Size}} {{.Reclaimable}}' 2>/dev/null | head -3 | tr '\n' '; ')
        [ -n "$reclaim" ] && _ck_ok "docker disk usage" "$reclaim"
    fi
    if [ -n "$disk" ]; then
        local gb=$(( disk / 1024 ))
        _ck_ok "Docker VM disk allocation: ${gb} GB" \
            "modern DSS images are ~9-11 GB unpacked; era layers are shared (K4)"
    fi

    # -- catalogue --------------------------------------------------------
    if [ -f "$VERSIONS_FILE" ] && [ -f "$HUB_TAGS_FILE" ]; then
        _ck_ok "catalogue: $(catalog_versions | wc -l | tr -d ' ') versions, $(catalog_hub_tags | wc -l | tr -d ' ') on Hub"
    else
        _ck_fail "catalogue data missing" "run: dss-lab catalog --refresh"
    fi

    # -- deep: prove emulation actually works -----------------------------
    if [ "$deep" -eq 1 ] && [ "$daemon_up" -eq 1 ]; then
        log_step "deep check: running an amd64 container (pulls a small image)"
        local got
        # shellcheck disable=SC2046
        got=$(docker run --rm $(docker_platform_args) alpine:3 uname -m 2>/dev/null || printf 'failed')
        if [ "$got" = "x86_64" ]; then
            _ck_ok "amd64 emulation verified: uname -m = x86_64"
        else
            _ck_fail "amd64 emulation check failed" "got: $got"
        fi
    elif [ "$deep" -eq 0 ]; then
        log_dim "  (run 'dss-lab doctor --deep' to actually execute an amd64 container)"
    fi

    doctor_report
}

doctor_report() {
    log_info ""
    if [ "$DOCTOR_FAIL" -gt 0 ]; then
        log_error "$DOCTOR_FAIL blocking issue(s), $DOCTOR_WARN warning(s)"
        return 2
    elif [ "$DOCTOR_WARN" -gt 0 ]; then
        log_warn "$DOCTOR_WARN warning(s), nothing blocking"
        return 1
    fi
    log_ok "all checks passed"
    return 0
}
