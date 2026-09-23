#!/usr/bin/env bash
# provision.sh — the machine-to-machine contract (docs/PROVISIONING.md).
#
# Licence -> admin API key -> register -> emit {nickname, url, api_key}.
# Unattended: nothing here prompts.

LICENSE_DIR="${DSS_LAB_LICENSE_DIR:-$HOME/.dataiku/licenses}"
DATAIKU_CONFIG="${DKU_CONFIG_FILE:-$HOME/.dataiku/config.json}"
APIKEY_LABEL="dss-mac-docker"

# Preference order: 2024 first — an older offer string is likelier to be
# understood by older DSS. Globs, never exact names: the user portion of the
# filename belongs to one licence set (DESIGN.md D9).
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

# LICENSE_2025_MIN_DSS — the 2025-tier licences are refused by any older DSS
# (docs/LICENCES.md). Skip them there rather than try and read a 400.
LICENSE_2025_MIN_DSS="12.6.0"

# license_supported <file> <version> — false only for a known-bad pairing
license_supported() {
    case "$(basename "$1")" in
        *2025*) version_ge "$2" "$LICENSE_2025_MIN_DSS" ;;
        *) return 0 ;;
    esac
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
        [ -n "$list" ] || die "no licence files in $LICENSE_DIR (put them there, or set DSS_LAB_LICENSE_DIR)"
    fi

    printf '%s\n' "$list" | while IFS= read -r c; do
        [ -n "$c" ] || continue
        exp=$(license_expiry "$c")
        if ! license_supported "$c" "$v"; then
            if [ -n "$explicit" ]; then
                log_warn "$(basename "$c") is a 2025-tier licence; DSS $v is older than $LICENSE_2025_MIN_DSS and will likely reject it" >&2
            else
                log_dim "skipping $(basename "$c"): 2025-tier licences need DSS $LICENSE_2025_MIN_DSS or later" >&2
                continue
            fi
        fi
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

# ------------------------------------------------------------ admin profile --
# A fresh DSS stores its admin user as DATA_SCIENTIST. A licence that does not
# offer that profile (the 2024 and 2025 tiers) makes DSS silently demote admin to
# the licence's fallback profile, which is EXPLORER on the 2024 tier: the API key
# works but admin cannot author anything. Read the truth off the live node.

# admin_profile_for_licence <file> — the maximum productive profile for the
# licence tier (docs/LICENCES.md). Empty for a file we cannot classify.
admin_profile_for_licence() {
    case "$(basename "$1")" in
        *2025*) printf 'FULL_DESIGNER' ;;
        *2024*) printf 'DESIGNER' ;;
        *2018*) printf 'DATA_SCIENTIST' ;;
    esac
}

# admin_profile_decide <stored> <target> <licensed profiles, space-separated>
# -> ok | set | unoffered | unknown. Only a stored profile the licence does NOT
# offer counts as demoted; one that is licensed is left alone, because someone
# may have chosen it on purpose.
admin_profile_decide() {
    local stored="$1" target="$2" licensed=" $3 "
    case "$licensed" in *" $stored "*) printf 'ok'; return 0 ;; esac
    [ -n "$target" ] || { printf 'unknown'; return 0; }
    case "$licensed" in *" $target "*) printf 'set' ;; *) printf 'unoffered' ;; esac
}

# _dss_get <url> <key> <path> — public API GET; body on stdout
_dss_get() { curl -s -m 30 -u "$2:" "$1/public/api$3"; }

# admin_profile_ensure <version> <licence_file> <url> <key>
# Prints admin's resulting stored profile on stdout, empty if it could not be
# determined. Never fails provisioning: a demoted admin is reported, not fatal.
admin_profile_ensure() {
    local v="$1" lic="$2" url="$3" key="$4" licensed stored target action
    licensed=$(_dss_get "$url" "$key" /admin/licensing/status | python3 -c "
import sys,json
try: print(' '.join(json.load(sys.stdin).get('base',{}).get('userProfiles',[])))
except Exception: pass" 2>/dev/null)
    stored=$(_dss_get "$url" "$key" /admin/users/admin | python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('userProfile') or '')
except Exception: pass" 2>/dev/null)
    if [ -z "$licensed" ] || [ -z "$stored" ]; then
        log_warn "could not read admin's profile from DSS $v; left unchanged" >&2
        return 0
    fi
    target=$(admin_profile_for_licence "$lic")
    action=$(admin_profile_decide "$stored" "$target" "$licensed")
    case "$action" in
        ok)
            log_dim "admin profile $stored is licensed" >&2 ;;
        unknown)
            log_warn "admin profile $stored is not offered by this licence, and $(basename "$lic") is not a known tier; left unchanged" >&2 ;;
        unoffered)
            log_warn "admin profile $stored is not offered, and neither is $target (this licence offers: $licensed); admin is demoted" >&2 ;;
        set)
            log_step "admin is stored as $stored, which this licence does not offer; setting $target" >&2
            docker exec "$(container_name "$v")" "$DSS_DATADIR/bin/dsscli" user-edit admin \
                --user-profile "$target" >/dev/null 2>&1 \
                || { log_warn "could not set admin's profile to $target" >&2; printf '%s' "$stored"; return 0; }
            stored=$(_dss_get "$url" "$key" /admin/users/admin | python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('userProfile') or '')
except Exception: pass" 2>/dev/null)
            if [ "$stored" = "$target" ]; then log_ok "admin profile is now $target" >&2
            else log_warn "admin profile reads back as '$stored', expected $target" >&2; fi ;;
    esac
    printf '%s' "$stored"
}

# ---------------------------------------------------------------- API keys --

# dsscli writes an "[INFO] [dsscli] Creating an admin key for dsscli" line to
# STDOUT on its first invocation in a container, ahead of the JSON. Strip
# anything before the first [ or { rather than trusting the stream to be clean.
_json_after_noise() {
    python3 -c "
import json,sys
raw=sys.stdin.read()
i=min([x for x in (raw.find('['), raw.find('{')) if x!=-1], default=-1)
if i<0: sys.exit(1)
try: json.dump(json.loads(raw[i:]), sys.stdout)
except Exception: sys.exit(1)
"
}

# apikey_valid <value> — DSS masks secrets in some versions' api-keys-list
# output: 13.x returns "******" where 12.x returns the real key. A masked value
# is a non-credential, and storing one hands the caller a key that 401s.
apikey_valid() {
    case "$1" in
        ''|*'*'*) return 1 ;;                 # empty, or contains a mask char
    esac
    [ "${#1}" -ge 16 ]
}

# apikey_from_config <nickname> — the key we previously recorded ourselves.
# This is the reliable source: it is the only place the plaintext secret is
# guaranteed to survive, since some DSS versions mask it on read-back.
apikey_from_config() {
    [ -f "$DATAIKU_CONFIG" ] || return 1
    NICK="$1" CFG="$DATAIKU_CONFIG" python3 -c "
import json,os,sys
try: d=json.load(open(os.environ['CFG']))
except Exception: sys.exit(1)
e=(d.get('dss_instances') or {}).get(os.environ['NICK'])
if not e or not e.get('api_key'): sys.exit(1)
print(e['api_key'])
" 2>/dev/null
}

# apikey_works <url> <key> — the only trustworthy validation is using it.
apikey_works() {
    local code
    code=$(curl -sS -o /dev/null -m 10 -u "$2:" -w '%{http_code}' \
            "$1$DSS_READY_PATH" 2>/dev/null) || true
    [ "$code" = "200" ]
}

# apikey_ensure <version> — return a WORKING admin key, minting only if needed.
#
# Order matters. A previously recorded key is checked first and confirmed by
# actually calling the API, because `api-keys-list` cannot be trusted to
# disclose the secret: DSS 13.x returns "******" where 12.x returns the real
# key. Believing that listing once stored a six-asterisk string as a credential.
apikey_ensure() {
    local v="$1" cname url key
    cname=$(container_name "$v")
    url=$(instance_url "$v" | tr -d "\n")

    # 1. our own record, proven by use
    key=$(apikey_from_config "$(container_name "$v")" || true)
    if [ -n "$key" ] && apikey_valid "$key" && apikey_works "$url" "$key"; then
        log_dim "reusing the recorded admin API key" >&2
        printf '%s' "$key"; return 0
    fi

    # 2. a listing, but only where this DSS version discloses the secret
    key=$(docker exec "$cname" "$DSS_DATADIR/bin/dsscli" api-keys-list --output json 2>/dev/null \
          | _json_after_noise 2>/dev/null \
          | APIKEY_LABEL="$APIKEY_LABEL" python3 -c "
import json,os,sys
for it in json.load(sys.stdin):
    if it.get('label')==os.environ['APIKEY_LABEL'] and it.get('admin'):
        print(it.get('key','')); break
" 2>/dev/null) || true
    if [ -n "$key" ] && apikey_valid "$key" && apikey_works "$url" "$key"; then
        log_dim "reusing existing admin API key labelled '$APIKEY_LABEL'" >&2
        printf '%s' "$key"; return 0
    fi

    # 3. mint. On versions that mask, the old key cannot be deleted by id
    # (api-key-delete takes the secret), so a replaced key is left behind.
    log_step "minting an admin API key" >&2
    key=$(docker exec "$cname" "$DSS_DATADIR/bin/dsscli" api-key-create \
            --admin true --label "$APIKEY_LABEL" \
            --description "provisioned by dss-lab" --output json 2>/dev/null \
          | _json_after_noise 2>/dev/null \
          | python3 -c "
import json,sys
d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d
print(d.get('key',''))
" 2>/dev/null)

    if ! apikey_valid "$key"; then
        log_error "DSS $v returned an unusable API key (length ${#key})" >&2
        return 1
    fi
    if ! apikey_works "$url" "$key"; then
        log_error "the minted API key does not authenticate against $url" >&2
        return 1
    fi
    printf '%s' "$key"
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

    # Belt and braces: everything before the final emit is forced to stderr, so
    # no docker subcommand can ever corrupt the JSON contract on stdout.
    # shellcheck disable=SC2086
    instance_up "$v" $migrate --timeout "$timeout" >&2 || return 1

    chosen=$(license_apply "$v" "$lic")
    [ -n "$chosen" ] || die "no licence was accepted by DSS $v"

    key=$(apikey_ensure "$v")
    [ -n "$key" ] || die "could not obtain an admin API key for DSS $v"

    url=$(instance_url "$v" | tr -d '\n')
    local admin_profile
    admin_profile=$(admin_profile_ensure "$v" "$chosen" "$url" "$key")
    nick=$(DSS_LAB_API_KEY="$key" register_instance "$v" "$url")

    if [ "$out" = "json" ]; then
        DSS_LAB_API_KEY="$key" NICK="$nick" URL="$url" V="$v" \
        CT="$(container_name "$v")" LIC="$chosen" DEPS="$(image_deps_check "$v")" \
        AP="$admin_profile" \
        python3 -c "
import json,os
print(json.dumps({
 'nickname': os.environ['NICK'], 'url': os.environ['URL'],
 'api_key': os.environ['DSS_LAB_API_KEY'], 'version': os.environ['V'],
 'container': os.environ['CT'], 'licence': os.environ['LIC'],
 'deps_check': os.environ['DEPS'], 'admin_profile': os.environ['AP'],
 'status': 'ready',
}, indent=2))
"
    else
        log_info ""
        printf 'nickname  %s\n' "$nick"
        printf 'url       %s\n' "$url"
        printf 'version   %s\n' "$v"
        printf 'licence   %s\n' "$chosen"
        printf 'deps_check %s\n' "$(image_deps_check "$v")"
        printf 'admin_profile %s\n' "$admin_profile"
        printf 'api_key   <%s chars — use --output json to emit it>\n' "${#key}"
        log_info ""
        log_dim "connect with dataiku-headless using nickname '$nick'"
    fi
}

# ------------------------------------------------------------------- seeding --

# seed_instance <version> [--slice NAME]
# A provisioned instance is empty, which makes it a weak upgrade-assessment
# target. Seeding creates content chosen for structural coverage, not volume.
# Deliberately per-era: object types absent on an older DSS stay absent, because
# that sparseness is signal the consumer wants to observe (docs/SEEDING.md).
seed_instance() {
    local v="$1"; shift
    local slice="cross-project" url key nick
    while [ $# -gt 0 ]; do
        case "$1" in
            --slice) slice="$2"; shift 2 ;;
            *) die "seed: unknown option $1" ;;
        esac
    done

    [ "$(instance_state "$v")" = "running" ] || die "DSS $v is not running (dss-lab up $v)"
    nick=$(container_name "$v")
    url=$(instance_url "$v" | tr -d '\n')
    key=$(apikey_from_config "$nick") || die "no recorded API key for $nick (dss-lab provision $v)"

    python3 "$DSS_LAB_ROOT/seed/dss_seed.py" --url "$url" --api-key "$key" --slice "$slice"
}
