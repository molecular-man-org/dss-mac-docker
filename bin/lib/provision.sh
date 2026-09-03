#!/usr/bin/env bash
# provision.sh — the machine-to-machine contract (docs/PROVISIONING.md).
#
# Licence -> admin API key -> register -> emit {nickname, url, api_key}.
# Unattended: nothing here prompts.

LICENSE_DIR="${DSS_LAB_LICENSE_DIR:-$HOME/Downloads/yournewinternalusagelicense}"
DATAIKU_CONFIG="${DKU_CONFIG_FILE:-$HOME/.dataiku/config.json}"
APIKEY_LABEL="dss-mac-docker"

# Preference order. Tim's direction: 2024 first — an older offer string is
# likelier to be understood by older DSS. Globs, never exact names: the
# "timhonker" portion belongs to one user's licence set (DESIGN.md D9).
LICENSE_GLOBS='dev-*-2024.json dev-*-2025-enterprise.json dev-*-2025-aiml.json dev-*-2025-analytics.json dev-*-2018.json'

# ---------------------------------------------------------------- licences --

# license_expiry <file> -> YYYYMMDD, or empty
license_expiry() {
    python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(d.get('content',{}).get('expiresOn',''))
except Exception:
    pass
" "$1" 2>/dev/null
}

license_expired() {
    local exp; exp=$(license_expiry "$1")
    [ -n "$exp" ] || return 1          # unparseable: let DSS decide
    [ "$exp" -lt "$(date +%Y%m%d)" ]
}

# license_candidates -> ordered list of readable licence files
license_candidates() {
    local g f
    [ -d "$LICENSE_DIR" ] || return 0
    for g in $LICENSE_GLOBS; do
        for f in "$LICENSE_DIR"/$g; do
            [ -f "$f" ] && printf '%s\n' "$f"
        done
    done
}

# license_apply <version> [explicit_file]
# Walks the preference order until DSS accepts one. Rejection is an expected
# outcome, not an error (KNOWN_ISSUES K10). Prints the winning filename.
license_apply() {
    local v="$1" explicit="${2:-}" c cname exp tried=0
    cname=$(container_name "$v")

    local list
    if [ -n "$explicit" ]; then
        [ -f "$explicit" ] || die "licence file not found: $explicit"
        list="$explicit"
    else
        list=$(license_candidates)
        [ -n "$list" ] || die "no licence files in $LICENSE_DIR (set DSS_LAB_LICENSE_DIR)"
    fi

    printf '%s\n' "$list" | while IFS= read -r c; do
        [ -n "$c" ] || continue
        exp=$(license_expiry "$c")
        if license_expired "$c"; then
            log_warn "skipping $(basename "$c"): expired on $exp" >&2
            continue
        fi
        log_step "applying $(basename "$c") (expires $exp)" >&2
        if docker cp "$c" "$cname:/tmp/dss-lab-license.json" >/dev/null 2>&1 &&
           docker exec "$cname" "$DSS_DATADIR/bin/dsscli" set-license \
                /tmp/dss-lab-license.json >/dev/null 2>&1; then
            docker exec "$cname" rm -f /tmp/dss-lab-license.json >/dev/null 2>&1 || true
            log_ok "licence accepted: $(basename "$c")" >&2
            printf '%s' "$(basename "$c")"
            return 0
        fi
        log_warn "DSS rejected $(basename "$c"); trying the next" >&2
        tried=$((tried + 1))
    done
}

# license_days_left — smallest days-to-expiry across candidates, for warnings
license_days_left() {
    local c best="" exp
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        exp=$(license_expiry "$c")
        [ -n "$exp" ] || continue
        if [ -z "$best" ] || [ "$exp" -gt "$best" ]; then best="$exp"; fi
    done <<EOF
$(license_candidates)
EOF
    [ -n "$best" ] || return 1
    python3 -c "
import datetime,sys
e=sys.argv[1]
d=datetime.date(int(e[:4]),int(e[4:6]),int(e[6:8]))
print((d-datetime.date.today()).days)
" "$best"
}

# ---------------------------------------------------------------- API keys --

# apikey_ensure <version> — reuse our labelled admin key if present, else mint.
# Without this, every provision call would leave another key behind.
apikey_ensure() {
    local v="$1" cname existing
    cname=$(container_name "$v")

    existing=$(docker exec "$cname" "$DSS_DATADIR/bin/dsscli" api-keys-list --output json 2>/dev/null \
        | APIKEY_LABEL="$APIKEY_LABEL" python3 -c "
import json,os,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for it in (d if isinstance(d,list) else [d]):
    if it.get('label')==os.environ['APIKEY_LABEL'] and it.get('admin'):
        print(it.get('key','')); break
" 2>/dev/null)

    if [ -n "$existing" ]; then
        log_dim "reusing existing admin API key labelled '$APIKEY_LABEL'" >&2
        printf '%s' "$existing"; return 0
    fi

    log_step "minting an admin API key" >&2
    docker exec "$cname" "$DSS_DATADIR/bin/dsscli" api-key-create \
        --admin true --label "$APIKEY_LABEL" \
        --description "provisioned by dss-lab" --output json 2>/dev/null \
      | python3 -c "
import json,sys
d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d
print(d['key'])
" 2>/dev/null
}

# -------------------------------------------------------------- registration --

# register_instance <version> <url>   (API key passed via DSS_LAB_API_KEY)
#
# ~/.dataiku/config.json holds the user's live production credentials
# (KNOWN_ISSUES K12). Read-modify-write, back up first, write atomically, touch
# only our own entry, and never change default_instance.
register_instance() {
    local v="$1" url="$2" nick
    nick=$(container_name "$v")

    mkdir -p "$(dirname "$DATAIKU_CONFIG")"
    if [ -f "$DATAIKU_CONFIG" ]; then
        local backup
        backup="$DATAIKU_CONFIG.bak-$(date +%Y%m%dT%H%M%S)"
        cp "$DATAIKU_CONFIG" "$backup" || die "could not back up $DATAIKU_CONFIG"
        log_dim "backed up config to $(basename "$backup")" >&2
    fi

    DSS_LAB_NICK="$nick" DSS_LAB_URL="$url" DSS_LAB_CFG="$DATAIKU_CONFIG" \
    DSS_LAB_DESC="DSS $v (dss-mac-docker)" python3 <<'PY' || die "failed to register instance"
import json, os, sys, tempfile

cfg_path = os.environ['DSS_LAB_CFG']
nick, url = os.environ['DSS_LAB_NICK'], os.environ['DSS_LAB_URL']
key, desc = os.environ['DSS_LAB_API_KEY'], os.environ['DSS_LAB_DESC']

cfg = {}
if os.path.exists(cfg_path):
    with open(cfg_path) as f:
        try:
            cfg = json.load(f)
        except Exception as e:
            # Never clobber a config we cannot parse — it holds real credentials.
            print(f"refusing to rewrite unparseable {cfg_path}: {e}", file=sys.stderr)
            sys.exit(1)

before = set((cfg.get('dss_instances') or {}).keys())
cfg.setdefault('dss_instances', {})[nick] = {
    'url': url, 'api_key': key, 'no_check_certificate': False, 'description': desc,
}
# default_instance is the user's choice; never touch it.

after = set(cfg['dss_instances'].keys())
lost = before - after
if lost:
    print(f"refusing to write: would drop instances {sorted(lost)}", file=sys.stderr)
    sys.exit(1)

d = os.path.dirname(cfg_path) or '.'
fd, tmp = tempfile.mkstemp(dir=d, prefix='.config.json.')
try:
    with os.fdopen(fd, 'w') as f:
        json.dump(cfg, f, indent=2)
        f.write('\n')
    os.chmod(tmp, 0o600)
    os.replace(tmp, cfg_path)
except Exception:
    os.path.exists(tmp) and os.unlink(tmp)
    raise
print(f"registered '{nick}' ({len(after)} instances in config)", file=sys.stderr)
PY
    printf '%s' "$nick"
}

# --------------------------------------------------------------- provision --

# provision <version> [--output json] [--license FILE] [--timeout N] [--migrate]
provision() {
    local v="$1"; shift
    local out=text lic="" timeout=1800 migrate="" nick url key chosen

    while [ $# -gt 0 ]; do
        case "$1" in
            --output)  out="$2"; shift 2 ;;
            --license) lic="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            --migrate) migrate="--migrate"; shift ;;
            *) die "provision: unknown option $1" ;;
        esac
    done

    local days; days=$(license_days_left 2>/dev/null || printf '')
    if [ -n "$days" ]; then
        if [ "$days" -lt 0 ]; then
            die "every licence in $LICENSE_DIR has expired (newest was $((0 - days)) days ago)"
        elif [ "$days" -lt 30 ]; then
            log_warn "licences expire in $days days (KNOWN_ISSUES K13)" >&2
        fi
    fi

    # shellcheck disable=SC2086
    instance_up "$v" $migrate --timeout "$timeout" || return 1

    chosen=$(license_apply "$v" "$lic")
    [ -n "$chosen" ] || die "no licence was accepted by DSS $v"

    key=$(apikey_ensure "$v")
    [ -n "$key" ] || die "could not obtain an admin API key for DSS $v"

    url=$(instance_url "$v" | tr -d '\n')
    nick=$(DSS_LAB_API_KEY="$key" register_instance "$v" "$url")

    if [ "$out" = "json" ]; then
        DSS_LAB_API_KEY="$key" NICK="$nick" URL="$url" V="$v" \
        CT="$(container_name "$v")" LIC="$chosen" python3 -c "
import json,os
print(json.dumps({
 'nickname': os.environ['NICK'], 'url': os.environ['URL'],
 'api_key': os.environ['DSS_LAB_API_KEY'], 'version': os.environ['V'],
 'container': os.environ['CT'], 'licence': os.environ['LIC'], 'status': 'ready',
}, indent=2))
"
    else
        log_info ""
        printf 'nickname  %s\n' "$nick"
        printf 'url       %s\n' "$url"
        printf 'version   %s\n' "$v"
        printf 'licence   %s\n' "$chosen"
        printf 'api_key   <%s chars — use --output json to emit it>\n' "${#key}"
        log_info ""
        log_dim "connect with dataiku-headless using nickname '$nick'"
    fi
}
