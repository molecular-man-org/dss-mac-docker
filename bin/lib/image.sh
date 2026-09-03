#!/usr/bin/env bash
# image.sh — building DSS images for versions that Docker Hub does not publish.
#
# Only 14 of the 109 in-range versions are on Hub (RESEARCH.md §3), so this is
# the primary path, not a fallback.

# era_puppeteer <era> — the puppeteer pin upstream used for that era
# (RESEARCH.md §6). Chart export is the only thing affected.
era_puppeteer() {
    case "$1" in
        dss11-12) printf '13.7.0' ;;
        dss13)    printf '23.11.1' ;;
        dss14-15) printf '24.8.2' ;;
        *) log_error "unknown era: $1"; return 1 ;;
    esac
}

# kit_url <version>
kit_url() {
    printf 'https://cdn.downloads.dataiku.com/public/studio/%s/dataiku-dss-%s.tar.gz' "$1" "$1"
}

# kit_available <version> — cheap existence probe before a long build
kit_available() {
    local code
    code=$(curl -sS -o /dev/null -m 20 -w '%{http_code}' -r 0-0 "$(kit_url "$1")" 2>/dev/null || printf '000')
    case "$code" in 200|206) return 0 ;; *) return 1 ;; esac
}

# image_build <version> [--era-base scratch|hub] [--no-cache]
image_build() {
    local v="$1"; shift
    local era base pup ref extra=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-cache) extra="$extra --no-cache"; shift ;;
            --era-base)
                [ "$2" = "scratch" ] && die "--era-base scratch is not implemented (see docs/ROADMAP.md phase 3)"
                shift 2 ;;
            *) die "build: unknown option $1" ;;
        esac
    done

    era=$(version_era "$v") || return 1
    base=$(era_base_image "$era")
    pup=$(era_puppeteer "$era")
    ref=$(image_local "$v")

    log_step "checking the installer kit exists for DSS $v"
    kit_available "$v" || die "no installer kit at $(kit_url "$v")"
    log_ok "kit available"

    if ! image_present "$base"; then
        log_step "pulling era base $base (shared by every $era version)"
        # shellcheck disable=SC2046
        docker pull $(docker_platform_args) "$base" || die "failed to pull era base $base"
    else
        log_dim "era base present: $base"
    fi

    log_step "building $ref from $base"
    log_dim "kit download + install only; the R build is inherited from the base"
    # shellcheck disable=SC2046,SC2086
    docker build \
        $(docker_platform_args) \
        $extra \
        --build-arg "BASE_IMAGE=$base" \
        --build-arg "DSS_VERSION_ARG=$v" \
        --build-arg "PUPPETEER_VERSION=$pup" \
        --label "$LABEL_PREFIX.managed=true" \
        --label "$LABEL_PREFIX.version=$v" \
        --label "$LABEL_PREFIX.era=$era" \
        -t "$ref" \
        -f "$DSS_LAB_ROOT/docker/Dockerfile.kit" \
        "$DSS_LAB_ROOT" || die "build failed for DSS $v"

    log_ok "built $ref"
}
