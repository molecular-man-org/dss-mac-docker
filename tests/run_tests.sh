#!/usr/bin/env bash
# run_tests.sh — unit tests for the pure functions. No Docker daemon required.

set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DSS_LAB_ROOT="$ROOT"
NO_COLOR=1; export NO_COLOR

# shellcheck source=../bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"
# shellcheck source=../bin/lib/catalog.sh
. "$ROOT/bin/lib/catalog.sh"
# shellcheck source=../bin/lib/image.sh
. "$ROOT/bin/lib/image.sh"
# shellcheck source=../bin/lib/instance.sh
. "$ROOT/bin/lib/instance.sh"
# shellcheck source=../bin/lib/provision.sh
. "$ROOT/bin/lib/provision.sh"

PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1" >&2; }

# assert_eq <label> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then ok; else bad "$1: expected '$2', got '$3'"; fi
}
# assert_true <label> <command...>
assert_true() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ok; else bad "$label: expected success"; fi
}
# assert_false <label> <command...>
assert_false() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then bad "$label: expected failure"; else ok; fi
}

section() { printf '\n%s\n' "$1"; }

# ------------------------------------------------------------ version_valid --
section "version_valid"
for v in 12.3.0 11.0.0 15.0.0 100.20.30; do assert_true "valid $v" version_valid "$v"; done
for v in "" 12.3 v12.3.0 12.3.0.1 12.3.x "12 3 0" abc; do
    assert_false "invalid $v" version_valid "$v"
done

# --------------------------------------------------------- version_in_range --
section "version_in_range (floor is 11.0.0)"
for v in 11.0.0 12.6.7 15.0.0; do assert_true "in range $v" version_in_range "$v"; done
for v in 10.0.9 8.0.2 4.3.3; do assert_false "out of range $v" version_in_range "$v"; done

# ---------------------------------------------------------------- port math --
section "version_port"
assert_eq "11.0.0" 10000 "$(version_port 11.0.0)"
assert_eq "12.3.0" 11300 "$(version_port 12.3.0)"
assert_eq "12.6.7" 11670 "$(version_port 12.6.7)"
assert_eq "13.5.7" 12570 "$(version_port 13.5.7)"
assert_eq "14.4.1" 13410 "$(version_port 14.4.1)"
assert_eq "14.7.3" 13730 "$(version_port 14.7.3)"
assert_eq "15.0.0" 14000 "$(version_port 15.0.0)"

section "version_port is collision-free across the whole catalogue"
dupes=$(for v in $(catalog_versions); do version_port "$v"; printf '\n'; done | sort | uniq -d | wc -l | tr -d ' ')
total=$(catalog_versions | wc -l | tr -d ' ')
distinct=$(for v in $(catalog_versions); do version_port "$v"; printf '\n'; done | sort -u | wc -l | tr -d ' ')
assert_eq "no duplicate ports" 0 "$dupes"
assert_eq "distinct ports == version count" "$total" "$distinct"

section "version_port_is_canonical"
assert_true  "12.6.7 canonical"      version_port_is_canonical 12.6.7
assert_false "12.10.0 not canonical" version_port_is_canonical 12.10.0
assert_false "12.0.10 not canonical" version_port_is_canonical 12.0.10

# --------------------------------------------------------------------- era --
section "version_era boundaries"
assert_eq "11.0.0" dss11-12 "$(version_era 11.0.0)"
assert_eq "11.4.5" dss11-12 "$(version_era 11.4.5)"
assert_eq "12.0.0" dss11-12 "$(version_era 12.0.0)"
assert_eq "12.6.7" dss11-12 "$(version_era 12.6.7)"
assert_eq "13.0.0" dss13    "$(version_era 13.0.0)"
assert_eq "13.5.7" dss13    "$(version_era 13.5.7)"
assert_eq "14.0.0" dss14-15 "$(version_era 14.0.0)"
assert_eq "14.7.3" dss14-15 "$(version_era 14.7.3)"
assert_eq "15.0.0" dss14-15 "$(version_era 15.0.0)"
assert_false "10.0.9 has no era" version_era 10.0.9

section "era_base_image"
assert_eq "dss11-12" "dataiku/dss:12.6.4" "$(era_base_image dss11-12)"
assert_eq "dss13"    "dataiku/dss:13.4.4" "$(era_base_image dss13)"
assert_eq "dss14-15" "dataiku/dss:15.0.0" "$(era_base_image dss14-15)"
assert_false "unknown era rejected" era_base_image nonsense

section "era base is itself in its era, and published on Hub"
for era in dss11-12 dss13 dss14-15; do
    base=$(era_base_image "$era"); tag="${base##*:}"
    assert_eq "$era base era matches" "$era" "$(version_era "$tag")"
    assert_true "$era base $tag is on Hub" catalog_hub_tags_has "$tag"
done

# -------------------------------------------------------------- identities --
section "derived identities"
assert_eq "container" "dss-12.3.0"                 "$(container_name 12.3.0)"
assert_eq "volume"    "dss-12.3.0-data"            "$(volume_name 12.3.0)"
assert_eq "hub image" "dataiku/dss:14.4.1"         "$(image_hub 14.4.1)"
assert_eq "local img" "dss-mac-docker/dss:12.3.0"  "$(image_local 12.3.0)"
assert_eq "url"       "http://localhost:11300"     "$(instance_url 12.3.0)"

# ----------------------------------------------------------------- catalog --
section "catalogue integrity"
assert_eq "109 versions in range" 109 "$(catalog_versions | wc -l | tr -d ' ')"
assert_eq "14 Hub tags in range"  14  "$(catalog_hub_tags | wc -l | tr -d ' ')"
bad_range=$(catalog_versions | while read -r v; do version_in_range "$v" || printf 'x'; done | wc -c | tr -d ' ')
assert_eq "every catalogued version is in range" 0 "$bad_range"
orphans=$(catalog_hub_tags | while read -r t; do catalog_known "$t" || printf '%s ' "$t"; done)
assert_eq "every Hub tag is a known version" "" "$orphans"

section "catalog_source"
assert_eq "14.4.1 on Hub"      pull  "$(catalog_source 14.4.1)"
assert_eq "12.6.4 on Hub"      pull  "$(catalog_source 12.6.4)"
assert_eq "12.3.0 needs build" build "$(catalog_source 12.3.0)"
assert_eq "14.7.3 needs build" build "$(catalog_source 14.7.3)"

# ----------------------------------------------------------------- resolve --
section "catalog_resolve"
assert_eq "exact"          12.3.0 "$(catalog_resolve 12.3.0)"
assert_eq "leading v"      12.3.0 "$(catalog_resolve v12.3.0)"
assert_eq "uppercase V"    12.3.0 "$(catalog_resolve V12.3.0)"
assert_eq "dss prefix"     12.3.0 "$(catalog_resolve 'DSS 12.3.0')"
assert_eq "dss v prefix"   12.3.0 "$(catalog_resolve 'dss v12.3.0')"
assert_eq "major only"     14.7.3 "$(catalog_resolve 14)"
assert_eq "major.minor"    12.3.2 "$(catalog_resolve 12.3)"
assert_eq "latest"         15.0.0 "$(catalog_resolve latest)"
assert_eq "newest"         15.0.0 "$(catalog_resolve newest)"
assert_eq "line 13"        13.5.7 "$(catalog_resolve 13)"
assert_eq "line 11"        11.4.5 "$(catalog_resolve 11)"

section "catalog_resolve rejects"
assert_false "unknown patch"   catalog_resolve 12.9.9
assert_false "below floor"     catalog_resolve 8.0.2
assert_false "unknown line"    catalog_resolve 99
assert_false "garbage"         catalog_resolve "not-a-version"
assert_false "empty"           catalog_resolve ""

# ------------------------------------------------------------- build inputs --
section "era_puppeteer (upstream pins, RESEARCH §6)"
assert_eq "dss11-12" 13.7.0  "$(era_puppeteer dss11-12)"
assert_eq "dss13"    23.11.1 "$(era_puppeteer dss13)"
assert_eq "dss14-15" 24.8.2  "$(era_puppeteer dss14-15)"
assert_false "unknown era rejected" era_puppeteer nope

section "kit_url"
assert_eq "12.3.1" \
  "https://cdn.downloads.dataiku.com/public/studio/12.3.1/dataiku-dss-12.3.1.tar.gz" \
  "$(kit_url 12.3.1)"

section "image_ref follows catalog_source"
assert_eq "12.6.4 is on Hub"   "dataiku/dss:12.6.4"        "$(image_ref 12.6.4)"
assert_eq "12.3.1 is built"    "dss-mac-docker/dss:12.3.1" "$(image_ref 12.3.1)"

section "major_base_image keeps the major aligned"
assert_eq "11.4.5" "dataiku/dss:11.2.0" "$(major_base_image 11.4.5)"
assert_eq "12.3.1" "dataiku/dss:12.6.4" "$(major_base_image 12.3.1)"
assert_eq "13.5.7" "dataiku/dss:13.4.4" "$(major_base_image 13.5.7)"
assert_eq "14.7.3" "dataiku/dss:14.7.0" "$(major_base_image 14.7.3)"
assert_eq "15.0.0" "dataiku/dss:15.0.0" "$(major_base_image 15.0.0)"
for v in 11.4.5 12.3.1 13.5.7 14.7.3 15.0.0; do
    b="$(major_base_image "$v")"; t="${b##*:}"
    assert_eq "base of $v shares its major" "$(version_major "$v")" "$(version_major "$t")"
    assert_true "base $t is a real Hub tag" catalog_hub_tags_has "$t"
done

section "build_base_for falls back to the major base when nothing is local"
# (image_present is false for these in a test env with no such images)
# sh -c would lose the sourced functions, so call them directly
for v in 13.5.7 14.7.3 11.4.5; do
    b="$(build_base_for "$v")"
    case "$b" in
        dataiku/dss:*)
            t="${b##*:}"
            assert_true "base for $v ($b) is a real Hub tag" catalog_hub_tags_has "$t" ;;
        *) bad "build_base_for $v returned '$b', not a Hub ref" ;;
    esac
done

section "every era base is a real, pullable Hub tag"
for era in dss11-12 dss13 dss14-15; do
    tag="$(era_base_image "$era")"; tag="${tag##*:}"
    assert_true "$tag published" catalog_hub_tags_has "$tag"
done

# ---------------------------------------------------------------- licences --
section "licence expiry parsing"
LICTMP=$(mktemp -d)
cat > "$LICTMP/dev-x-2024.json" <<'JSON'
{"content":{"expiresOn":20260929,"licenseKind":"DATAIKU_INTERNAL"}}
JSON
cat > "$LICTMP/dev-x-2018.json" <<'JSON'
{"content":{"expiresOn":20200101,"licenseKind":"DATAIKU_INTERNAL"}}
JSON
cat > "$LICTMP/dev-x-2025-enterprise.json" <<'JSON'
{"content":{"expiresOn":20260929}}
JSON
assert_eq "parses expiresOn" 20260929 "$(license_expiry "$LICTMP/dev-x-2024.json")"
assert_false "2026 licence is not expired" license_expired "$LICTMP/dev-x-2024.json"
assert_true  "2020 licence IS expired"     license_expired "$LICTMP/dev-x-2018.json"

section "licence preference order — 2024 first (Tim's direction)"
# shellcheck disable=SC2034  # consumed by license_candidates in provision.sh
LICENSE_DIR="$LICTMP"
first=$(license_candidates | head -1 | xargs basename 2>/dev/null)
assert_eq "2024 sorts first" "dev-x-2024.json" "$first"
last=$(license_candidates | tail -1 | xargs basename 2>/dev/null)
assert_eq "2018 sorts last" "dev-x-2018.json" "$last"
assert_eq "all three listed" 3 "$(license_candidates | wc -l | tr -d ' ')"
rm -rf "$LICTMP"

# ------------------------------------------------- config merge safety (K12) --
# ~/.dataiku/config.json holds live production API keys. These assertions exist
# so the merge can never silently regress into a clobber.
section "register_instance never loses existing instances (K12)"
CFGTMP=$(mktemp -d)
DATAIKU_CONFIG="$CFGTMP/config.json"
cat > "$DATAIKU_CONFIG" <<'JSON'
{"default_instance":"prod",
 "dss_instances":{
   "prod":{"url":"https://prod.example","api_key":"PRODKEY","no_check_certificate":false,"description":"Prod"},
   "staging":{"url":"https://stg.example","api_key":"STGKEY","no_check_certificate":true,"description":"Stg"}}}
JSON
( DSS_LAB_API_KEY=NEWKEY register_instance 12.6.4 http://localhost:11640 ) >/dev/null 2>&1
python3 - "$DATAIKU_CONFIG" <<'PYCHK'
import json,sys
d=json.load(open(sys.argv[1])); i=d['dss_instances']
ok = (d['default_instance']=='prod'
      and len(i)==3
      and i['prod']['api_key']=='PRODKEY' and i['staging']['api_key']=='STGKEY'
      and i['staging']['no_check_certificate'] is True
      and i['dss-12.6.4']['url']=='http://localhost:11640'
      and i['dss-12.6.4']['api_key']=='NEWKEY')
sys.exit(0 if ok else 1)
PYCHK
if [ $? -eq 0 ]; then ok; else bad "K12: merge altered or dropped existing instances"; fi
assert_true "a backup was written" sh -c "ls '$CFGTMP'/config.json.bak-* >/dev/null 2>&1"

section "register_instance refuses to overwrite an unparseable config (K12)"
printf 'this is not json{{{' > "$DATAIKU_CONFIG"
( DSS_LAB_API_KEY=NEWKEY register_instance 12.6.4 http://localhost:11640 ) >/dev/null 2>&1
if grep -q 'not json' "$DATAIKU_CONFIG"; then ok
else bad "K12: clobbered a config it could not parse"; fi
rm -rf "$CFGTMP"

# ------------------------------------------------------- licence containment --
# A leaked licence file is the worst thing this repo could commit, and the
# obvious pattern (*license*.json) matches none of the real filenames. Assert on
# realistic names so the gitignore cannot silently regress.
section "licence files cannot be committed"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    for name in dev-timhonker-2024.json dev-timhonker-2025-enterprise.json \
                dev-anyuser-2018.json license.json licence.json; do
        if git -C "$ROOT" check-ignore -q "$ROOT/$name" 2>/dev/null; then ok
        else bad "licence containment: '$name' would NOT be ignored"; fi
    done
    for name in licenses/x.json licences/x.json; do
        if git -C "$ROOT" check-ignore -q "$ROOT/$name" 2>/dev/null; then ok
        else bad "licence containment: '$name' would NOT be ignored"; fi
    done
    # Guard against over-reach: tracked data files must stay visible.
    if git -C "$ROOT" check-ignore -q "$ROOT/data/versions-11plus.txt" 2>/dev/null
    then bad "gitignore is too broad: data/versions-11plus.txt is ignored"
    else ok; fi
else
    printf 'skip  not a git repo\n'
fi

# --------------------------------------------------- docs match code (CLI) --
# A help text that drifts from the dispatcher is how an agent ends up calling a
# command that does not exist. Assert the two agree, both directions.
section "every dispatched command appears in the help text"
HELP=$("$ROOT/bin/dss-lab" --help 2>&1)
DISPATCHED=$(sed -n '/^main()/,/^}/p' "$ROOT/bin/dss-lab" \
    | grep -oE '^[[:space:]]+[a-z|]+\)' | tr -d ' )' | tr '|' '\n' \
    | grep -vE '^$|^\*$' | sort -u)
for c in $DISPATCHED; do
    case "$c" in -h|--help|help) continue ;; esac
    if printf '%s' "$HELP" | grep -qw -- "$c"; then ok
    else bad "command '$c' is dispatched but missing from --help"; fi
done

section "every command the help text names is actually dispatched"
# Only the command sections list commands; USAGE and SPECS use the same
# indentation for the invocation line and for version-spec examples.
HELP_CMDS=$(printf '%s' "$HELP" | awk '
    /^[A-Z][A-Z ()+-]*$/ { sec = ($0 ~ /^(READY|LIFECYCLE|PROVISIONING|PLANNED)/) ? 1 : 0; next }
    sec && /^    [a-z]/  { print $1 }
' | sort -u)
for c in $HELP_CMDS; do
    if printf '%s' "$DISPATCHED" | grep -qx "$c"; then ok
    else bad "help names '$c' but main() does not dispatch it"; fi
done

section "documented commands resolve (no stale names in docs)"
for c in $(grep -ohE 'dss-lab [a-z]+' "$ROOT"/docs/*.md "$ROOT"/README.md 2>/dev/null \
           | awk '{print $2}' | sort -u); do
    if printf '%s' "$DISPATCHED" | grep -qx "$c"; then ok
    else bad "docs reference 'dss-lab $c' but it is not a command"; fi
done

# ------------------------------------------------------------------ report --
printf '\n----------------------------------------\n'
if [ "$FAIL" -eq 0 ]; then
    printf 'ok      %d assertions passed\n' "$PASS"
    exit 0
fi
printf 'FAILED  %d passed, %d failed\n' "$PASS" "$FAIL"
exit 1
