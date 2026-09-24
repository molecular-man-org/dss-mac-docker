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
# shellcheck source=../bin/lib/snapshot.sh
. "$ROOT/bin/lib/snapshot.sh"
# shellcheck source=../bin/lib/bundle.sh
. "$ROOT/bin/lib/bundle.sh"

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
{"content":{"expiresOn":20260929,"licenseKind":"EXAMPLE"}}
JSON
cat > "$LICTMP/dev-x-2018.json" <<'JSON'
{"content":{"expiresOn":20200101,"licenseKind":"EXAMPLE"}}
JSON
cat > "$LICTMP/dev-x-2025-enterprise.json" <<'JSON'
{"content":{"expiresOn":20260929}}
JSON
assert_eq "parses expiresOn" 20260929 "$(license_expiry "$LICTMP/dev-x-2024.json")"
assert_false "2026 licence is not expired" license_expired "$LICTMP/dev-x-2024.json"
assert_true  "2020 licence IS expired"     license_expired "$LICTMP/dev-x-2018.json"

section "licence preference order — 2024 first "
# shellcheck disable=SC2034  # consumed by license_candidates in provision.sh
LICENSE_DIR="$LICTMP"
first=$(license_candidates | head -1 | xargs basename 2>/dev/null)
assert_eq "2024 sorts first" "dev-x-2024.json" "$first"
last=$(license_candidates | tail -1 | xargs basename 2>/dev/null)
assert_eq "2018 sorts last" "dev-x-2018.json" "$last"
assert_eq "all three listed" 3 "$(license_candidates | wc -l | tr -d ' ')"
rm -rf "$LICTMP"

section "apikey_valid rejects masked and short secrets"
assert_false "empty rejected"      apikey_valid ""
assert_false "all-asterisk rejected" apikey_valid "******"
assert_false "partially masked"    apikey_valid "abc***def***ghi***xyz"
assert_false "too short"           apikey_valid "abc123"
assert_true  "32-char key ok"      apikey_valid "0123456789abcdef0123456789abcdef"
assert_true  "39-char key ok"      apikey_valid "0123456789abcdef0123456789abcdef0123456"

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

# ------------------------------------------------- snapshots and upgrades --
section "kit-puppeteer.sh evaluates the kit's own selection block"
KP=$(mktemp -d); mkdir -p "$KP/bin"
printf '#!/bin/sh\necho "$FAKE_NODE"\n' > "$KP/bin/node"; chmod +x "$KP/bin/node"
cat > "$KP/kit.sh" <<'KITEOF'
echo "[+] before the block"
node_version=$(node -v)
node_version=${node_version:1}
echo "+ Detected Node.js version ${node_version}"
IFS='.' read -r -a node_version_components <<< "${node_version}"
node_version_major=$((${node_version_components[0]}))
if [ $node_version_major -lt 10 ]; then
  echo "[-] unsupported"; exit 1
elif [ $node_version_major -lt 14 ]; then
  puppeteer_version="13.7.0"
elif [ $node_version_major -lt 16 ]; then
  puppeteer_version="19.11.1"
else
  puppeteer_version="21.3.6"
fi
echo "+ Installing Puppeteer ${puppeteer_version}"
touch "$KP_SENTINEL"
npm install puppeteer@${puppeteer_version} fs
KITEOF
kp() { PATH="$KP/bin:$PATH" FAKE_NODE="$1" KP_SENTINEL="$KP/ran" "$ROOT/docker/kit-puppeteer.sh" "${2:-$KP/kit.sh}"; }
assert_eq "node 20 -> newest"        "21.3.6" "$(kp v20.12.2)"
assert_eq "node 12 -> oldest"        "13.7.0" "$(kp v12.0.0)"
assert_eq "node 15 -> middle"        "19.11.1" "$(kp v15.1.0)"
assert_eq "unsupported node -> nothing" "" "$(kp v9.0.0)"
assert_eq "missing script -> nothing"   "" "$(kp v20.0.0 "$KP/absent.sh")"
echo "no selection block here" > "$KP/other.sh"
assert_eq "unrecognised script -> nothing" "" "$(kp v20.0.0 "$KP/other.sh")"
# Only the selection block may run: the touch and npm after it must not.
if [ -e "$KP/ran" ]; then bad "kit-puppeteer.sh ran code beyond the selection block"; else ok; fi
rm -rf "$KP"
# The Dockerfile must use it, with the era pin only as a fallback.
if grep -q 'kit-puppeteer.sh' "$ROOT/docker/Dockerfile.kit" && grep -q 'puppeteer@${PUP}' "$ROOT/docker/Dockerfile.kit"; then ok
else bad "Dockerfile.kit must install the puppeteer version the kit selects"; fi

section "bundle validation"
BT=$(mktemp -d)
python3 - "$BT" <<'PYEOF'
import sys, zipfile
d = sys.argv[1]
with zipfile.ZipFile(d + "/good.zip", "w") as z: z.writestr("export-manifest.json", "{}")
with zipfile.ZipFile(d + "/good2.zip", "w") as z: z.writestr("project_config/params.json", "{}")
with zipfile.ZipFile(d + "/rootjson.zip", "w") as z: z.writestr("project.json", "{}")
with zipfile.ZipFile(d + "/noproject.zip", "w") as z: z.writestr("readme.txt", "x")
open(d + "/notzip.zip", "w").write("this is not a zip")
PYEOF
assert_true  "project export accepted"     bundle_validate "$BT/good.zip"
assert_true  "params.json marker accepted" bundle_validate "$BT/good2.zip"
assert_false "zip without a marker"        bundle_validate "$BT/noproject.zip"
assert_false "a root project.json is not a marker" bundle_validate "$BT/rootjson.zip"
assert_false "not a zip"                   bundle_validate "$BT/notzip.zip"
assert_false "missing file"                bundle_validate "$BT/absent.zip"
assert_true  "remap OLD=NEW ok"            bundle_remap_valid "db_old=db_new"
for r in "" "nothing" "=new" "old=" "a=b=c"; do assert_false "remap bad '$r'" bundle_remap_valid "$r"; done
out=$(bundle_import 12.6.4 "$BT/good.zip" --remap-connection oops 2>&1); rc=$?
assert_eq "bad remap rejected before docker" "1" "$rc"
# dss-lab runs under set -e, so the import call must capture its exit code or a
# failed import would skip the cleanup and error message (found live).
if sed -n '/^bundle_import()/,/^}/p' "$ROOT/bin/lib/bundle.sh" | grep -q 'BUNDLE_TMP" || rc=\$?'; then ok
else bad "bundle_import must capture dsscli's exit code with '|| rc=\$?'"; fi
rm -rf "$BT"

section "admin profile follows the licence tier (docs/LICENCES.md)"
assert_eq "2025 -> FULL_DESIGNER"  FULL_DESIGNER  "$(admin_profile_for_licence dev-x-2025-enterprise.json)"
assert_eq "2025 aiml"              FULL_DESIGNER  "$(admin_profile_for_licence /a/dev-x-2025-aiml.json)"
assert_eq "2024 -> DESIGNER"       DESIGNER       "$(admin_profile_for_licence dev-x-2024.json)"
assert_eq "2018 -> DATA_SCIENTIST" DATA_SCIENTIST "$(admin_profile_for_licence dev-x-2018.json)"
assert_eq "unknown tier is empty"  ""             "$(admin_profile_for_licence custom.json)"
P24="DESIGNER PLATFORM_ADMIN VISUAL_DESIGNER EXPLORER AI_CONSUMER READER NONE"
assert_eq "demoted admin is fixed"        set       "$(admin_profile_decide DATA_SCIENTIST DESIGNER "$P24")"
assert_eq "licensed admin left alone"     ok        "$(admin_profile_decide VISUAL_DESIGNER DESIGNER "$P24")"
assert_eq "already on target"             ok        "$(admin_profile_decide DESIGNER DESIGNER "$P24")"
assert_eq "target not offered"            unoffered "$(admin_profile_decide DATA_SCIENTIST FULL_DESIGNER "$P24")"
assert_eq "unclassifiable licence"        unknown   "$(admin_profile_decide DATA_SCIENTIST "" "$P24")"
# PLATFORM_ADMIN is offered by every tier but must never be the target: it is an
# administrative identity, not the productive-access profile.
for f in dev-x-2025-aiml.json dev-x-2024.json dev-x-2018.json; do
    case "$(admin_profile_for_licence "$f")" in PLATFORM_ADMIN|ADMIN|TECHNICAL_ACCOUNT) bad "$f targets an admin profile" ;; *) ok ;; esac
done

section "version_ge"
assert_true  "equal is >="        version_ge 12.6.0 12.6.0
assert_true  "12.6.4 >= 12.6.0"   version_ge 12.6.4 12.6.0
assert_false "12.5.9 >= 12.6.0"   version_ge 12.5.9 12.6.0
assert_false "11.2.0 >= 12.6.0"   version_ge 11.2.0 12.6.0

section "2025 licences need DSS 12.6.0+ (docs/LICENCES.md)"
for f in dev-x-2025-enterprise.json dev-x-2025-aiml.json dev-x-2025-analytics.json; do
    assert_false "$f refused on 11.2.0" license_supported "$f" 11.2.0
    assert_false "$f refused on 12.5.9" license_supported "$f" 12.5.9
    assert_true  "$f allowed on 12.6.0" license_supported "$f" 12.6.0
    assert_true  "$f allowed on 14.7.3" license_supported "$f" 14.7.3
done
for f in dev-x-2024.json dev-x-2018.json; do
    assert_true "$f allowed on 11.2.0" license_supported "$f" 11.2.0
done

section "version_gt"
assert_true  "14.7.3 > 13.5.7"  version_gt 14.7.3 13.5.7
assert_true  "12.6.10 > 12.6.9" version_gt 12.6.10 12.6.9
assert_true  "13.0.0 > 12.9.9"  version_gt 13.0.0 12.9.9
assert_false "equal is not >"   version_gt 12.3.0 12.3.0
assert_false "12.6.4 > 12.6.7"  version_gt 12.6.4 12.6.7
assert_false "11.2.0 > 15.0.0"  version_gt 11.2.0 15.0.0

section "upgrade_check refuses downgrades and no-ops"
assert_true  "13.4.4 -> 14.7.0 allowed"      upgrade_check 13.4.4 14.7.0
assert_true  "12.6.4 -> 12.6.7 allowed"      upgrade_check 12.6.4 12.6.7
assert_false "same version refused"          upgrade_check 12.6.4 12.6.4
assert_false "downgrade refused"             upgrade_check 14.7.3 13.5.7
assert_false "patch downgrade refused"       upgrade_check 12.6.7 12.6.4

section "snapshot naming"
assert_eq "volume name" "dss-12.6.4-snap-before" "$(snapshot_volume 12.6.4 before)"
for n in before 20260923-101500 pre_upgrade v1.2; do assert_true "name ok $n" snapshot_name_valid "$n"; done
for n in "" "-lead" "has space" "a/b" "semi;colon" "x:y"; do assert_false "name bad '$n'" snapshot_name_valid "$n"; done
# A snapshot volume must never look like an instance to `ls` and `gc`, which
# select on the managed label.
if grep -q 'managed=true' <(sed -n '/^snapshot_create()/,/^}/p' "$ROOT/bin/lib/snapshot.sh"); then
    bad "snapshot volumes must not carry the managed label"; else ok; fi
# The upgrade target volume is labelled with the TARGET version, because labels
# are immutable; labelling it with the source would make the guard refuse every
# later `up`.
if sed -n '/^instance_upgrade()/,/^}/p' "$ROOT/bin/lib/snapshot.sh" | grep -q 'version=\$to'; then ok
else bad "upgrade must label the new volume with the target version"; fi
if sed -n '/^instance_upgrade()/,/^}/p' "$ROOT/bin/lib/snapshot.sh" | grep -q 'rm -f\|volume rm "\$(volume_name "\$from")"'; then
    bad "upgrade must never remove the source datadir"; else ok; fi
# Restore is destructive and nothing prompts, so it must demand --force.
out=$(snapshot_restore 12.6.4 x 2>&1); rc=$?
assert_eq "restore without --force exits 1" "1" "$rc"
assert_true "restore without --force says why" grep -q -e "--force" <<<"$out"

# ------------------------------------------------------- licence containment --
# A leaked licence file is the worst thing this repo could commit, and the
# obvious pattern (*license*.json) matches none of the real filenames. Assert on
# realistic names so the gitignore cannot silently regress.
section "licence files cannot be committed"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    for name in dev-example-2024.json dev-example-2025-enterprise.json \
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

section "stop uses a grace period long enough for supervisord"
assert_true "DSS_STOP_TIMEOUT is set" test -n "${DSS_STOP_TIMEOUT:-}"
assert_true "and is well above docker's 10s default" test "${DSS_STOP_TIMEOUT:-0}" -ge 60
if grep -q 'docker stop -t "$DSS_STOP_TIMEOUT"' "$ROOT/bin/lib/instance.sh"; then ok
else bad "instance_stop does not pass an explicit -t timeout"; fi

# ------------------------------------------------------------- tools compile --
# tools/ holds reusable research scripts. They are not exercised by this suite,
# so at minimum they must stay importable rather than rot silently.
section "tools/ scripts compile"
for f in "$ROOT"/tools/*.py; do
    [ -f "$f" ] || continue
    if python3 -m py_compile "$f" 2>/dev/null; then ok
    else bad "tools: $(basename "$f") does not compile"; fi
done

# ---------------------------------------------------------------- lint gate --
# Docs lint was bypassed three times because it lived in a shell one-liner whose
# && guarded only an echo, not the commit. Same lesson as everything else today:
# structure survives a tired session, remembering to check does not.
section "markdown lint"
if command -v markdownlint >/dev/null 2>&1; then
    if markdownlint "$ROOT" >/dev/null 2>&1; then ok
    else bad "markdownlint reports violations (run: markdownlint .)"; fi
else
    printf 'skip  markdownlint not installed\n'
fi

# ------------------------------------------------------------------ report --
printf '\n----------------------------------------\n'
if [ "$FAIL" -eq 0 ]; then
    printf 'ok      %d assertions passed\n' "$PASS"
    exit 0
fi
printf 'FAILED  %d passed, %d failed\n' "$PASS" "$FAIL"
exit 1
