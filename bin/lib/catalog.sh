#!/usr/bin/env bash
# catalog.sh — version catalogue and spec resolution.
#
# The catalogue is checked into data/ rather than scraped at runtime, so
# `resolve` works offline and a network hiccup can never wedge a container
# start. `catalog --refresh` re-scrapes and rewrites those files.

DOWNLOADS_INDEX="https://downloads.dataiku.com/public/dss/"
HUB_TAGS_API="https://hub.docker.com/v2/repositories/dataiku/dss/tags/?page_size=100"

# ------------------------------------------------------------------ loading --

catalog_versions() {
    [ -f "$VERSIONS_FILE" ] || die "missing $VERSIONS_FILE (run: dss-lab catalog --refresh)"
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' "$VERSIONS_FILE"
}

catalog_hub_tags() {
    [ -f "$HUB_TAGS_FILE" ] || die "missing $HUB_TAGS_FILE (run: dss-lab catalog --refresh)"
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' "$HUB_TAGS_FILE"
}

# version_sort — numeric by major.minor.patch, ascending. `sort -V` is not
# dependable across platforms; this is.
version_sort() { sort -t. -k1,1n -k2,2n -k3,3n; }

# catalog_source <version> — pull if published on Hub, otherwise build
catalog_source() {
    if catalog_hub_tags | grep -qx "$1"; then printf 'pull'; else printf 'build'; fi
}

catalog_known() { catalog_versions | grep -qx "$1"; }

catalog_hub_tags_has() { catalog_hub_tags | grep -qx "$1"; }

# ----------------------------------------------------------------- resolve --

# catalog_resolve <spec> — a version spec to a concrete version.
#   latest | newest        -> highest known
#   14                     -> highest 14.x
#   12.3                   -> highest 12.3.x
#   12.3.0 | v12.3.0       -> exact, validated
# Leading v/V and any "dss" prefix are tolerated so the skill can pass a token
# lifted straight out of the user's phrasing.
catalog_resolve() {
    local spec="$1" cleaned match

    [ -n "$spec" ] || { log_error "no version given"; return 1; }

    cleaned=$(printf '%s' "$spec" \
        | tr 'A-Z' 'a-z' \
        | sed -E 's/^dss[[:space:]_-]*//; s/^v//; s/[[:space:]]//g')

    case "$cleaned" in
        latest|newest|current)
            catalog_versions | version_sort | tail -1
            return 0 ;;
    esac

    if printf '%s' "$cleaned" | grep -qE '^[0-9]+$'; then
        match=$(catalog_versions | grep -E "^${cleaned}\." | version_sort | tail -1)
    elif printf '%s' "$cleaned" | grep -qE '^[0-9]+\.[0-9]+$'; then
        match=$(catalog_versions | grep -E "^${cleaned}\." | version_sort | tail -1)
    elif printf '%s' "$cleaned" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        if catalog_known "$cleaned"; then
            match="$cleaned"
        else
            match=""
        fi
    else
        log_error "cannot parse version spec: $spec"
        return 1
    fi

    if [ -z "$match" ]; then
        log_error "no known DSS version matches: $spec"
        if version_valid "$cleaned" && ! version_in_range "$cleaned"; then
            log_dim "DSS $cleaned predates the supported floor ($MIN_MAJOR.0.0)"
        else
            log_dim "nearest: $(catalog_versions | grep -E "^$(printf '%s' "$cleaned" | cut -d. -f1)\." \
                | version_sort | tail -3 | tr '\n' ' ')"
        fi
        return 1
    fi

    printf '%s' "$match"
}

# ------------------------------------------------------------------- table --

# catalog_table [--major N] [--source pull|build]
catalog_table() {
    local filter_major="" filter_source="" v src era port n=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --major)  filter_major="$2"; shift 2 ;;
            --source) filter_source="$2"; shift 2 ;;
            *) die "catalog: unknown option $1" ;;
        esac
    done

    printf '%-9s  %-9s  %-6s  %-5s\n' "VERSION" "ERA" "SOURCE" "PORT"
    printf '%-9s  %-9s  %-6s  %-5s\n' "---------" "---------" "------" "-----"

    for v in $(catalog_versions | version_sort); do
        [ -n "$filter_major" ] && [ "$(version_major "$v")" != "$filter_major" ] && continue
        src=$(catalog_source "$v")
        [ -n "$filter_source" ] && [ "$src" != "$filter_source" ] && continue
        era=$(version_era "$v"); port=$(version_port "$v")
        printf '%-9s  %-9s  %-6s  %-5s\n' "$v" "$era" "$src" "$port"
        n=$((n + 1))
    done

    log_info ""
    log_dim "$n versions listed"
}

catalog_summary() {
    local total hub build ma
    total=$(catalog_versions | wc -l | tr -d ' ')
    hub=$(catalog_hub_tags | wc -l | tr -d ' ')
    build=$((total - hub))
    log_info "DSS versions in range: $total    on Docker Hub: $hub    build required: $build"
    log_info ""
    printf '%-6s  %-10s  %-6s  %s\n' "LINE" "VERSIONS" "ON HUB" "ERA"
    for ma in 11 12 13 14 15; do
        local n h
        n=$(catalog_versions | grep -cE "^$ma\." || true)
        h=$(catalog_hub_tags | grep -cE "^$ma\." || true)
        [ "$n" -eq 0 ] && continue
        printf '%-6s  %-10s  %-6s  %s\n' "$ma.x" "$n" "$h" "$(version_era "$ma.0.0")"
    done
}

# ----------------------------------------------------------------- refresh --

catalog_refresh() {
    local tmp_v tmp_h n_v n_h
    mkdir -p "$CACHE_DIR" "$DATA_DIR"
    tmp_v="$CACHE_DIR/versions.new"; tmp_h="$CACHE_DIR/hub.new"

    log_step "scraping $DOWNLOADS_INDEX"
    if ! curl -sS --max-time 45 "$DOWNLOADS_INDEX" \
        | grep -oE 'href="1[1-9][0-9]*\.[0-9]+\.[0-9]+/"' \
        | sed -E 's|href="([^/]+)/"|\1|' \
        | version_sort | uniq > "$tmp_v"; then
        die "failed to fetch the downloads index"
    fi
    n_v=$(wc -l < "$tmp_v" | tr -d ' ')
    [ "$n_v" -gt 0 ] || die "downloads index returned no versions; refusing to overwrite"

    log_step "querying Docker Hub tags"
    if ! curl -sS --max-time 45 "$HUB_TAGS_API" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('results',[]):
    n=r.get('name','')
    p=n.split('.')
    if len(p)==3 and all(x.isdigit() for x in p) and int(p[0])>=11:
        print(n)
" | version_sort | uniq > "$tmp_h"; then
        die "failed to fetch Docker Hub tags"
    fi
    n_h=$(wc -l < "$tmp_h" | tr -d ' ')
    [ "$n_h" -gt 0 ] || die "Hub returned no usable tags; refusing to overwrite"

    mv "$tmp_v" "$VERSIONS_FILE"
    mv "$tmp_h" "$HUB_TAGS_FILE"
    log_ok "catalogue refreshed: $n_v versions, $n_h on Hub"
}
