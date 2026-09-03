# Provisioning contract

**This is the repo's primary interface.** The main consumer is not a human but
another Claude project:
`~/source_code/dataiku-upgrade-planning/dss-headless-upgrade-planning-skill`,
which tests its compatibility matrix against a range of older DSS versions and
needs them provisioned on demand.

`/start-dss-container` is a human-facing veneer over the same path.

---

## The flow

```text
caller: "provision DSS 12.3.1"
   │
   ├─ 1. resolve spec ──────────────► 12.3.1
   ├─ 2. ensure container ──────────► pull or build, create, or start existing
   ├─ 3. apply licence ─────────────► from an untracked licence folder
   ├─ 4. mint an admin API key ─────► dsscli api-key-create --admin true
   ├─ 5. register the instance ─────► merge into ~/.dataiku/config.json
   └─ returns ──────────────────────► { url, api_key, nickname }
```

Every step is unattended. Nothing may prompt, and nothing may assume a browser.

## Output contract

`dss-lab provision <spec> --output json` emits exactly:

```json
{
  "nickname": "dss-12.3.1",
  "url": "http://localhost:11310",
  "api_key": "...",
  "version": "12.3.1",
  "container": "dss-12.3.1",
  "licence": "dev-timhonker-2024.json",
  "status": "ready"
}
```

The three fields the caller actually needs are **url**, **api_key** and
**nickname** — they map onto `dataiku-headless`'s `DKU_DSS_URL`, `DKU_API_KEY`
and `DKU_INSTANCE_NAME`.

## Candidate commands (user-supplied, 2026-09-03) — VERIFY BEFORE USE

Tim supplied this sketch, explicitly untested:

```bash
DSS_DATADIR="/home/dataiku/dss_data"
cd "$DSS_DATADIR"
./bin/dss start                                    # 1. start DSS if needed
./bin/dsscli ... set-admin-password ...            # 2. exact cmd varies by version
./bin/dssadmin ... set-license-file license.json   # 3. exact cmd varies by version
# 4. admin API key, via CLI if supported else REST once login works
```

Three notes before anyone runs it:

1. **The datadir path is different in our containers.** The official DSS image
   sets `DSS_DATADIR=/home/dataiku/dss` (RESEARCH §7), not `/home/dataiku/dss_data`.
   `dss_data` is the convention for a manual host install. Using it here fails.
2. **Step 1 is unnecessary.** `run.sh` is the container's entrypoint and already
   ends in `exec "$DSS_DATADIR"/bin/dss run`, so DSS is PID 1. Starting it again
   inside a running container is wrong. What we need instead is a **restart**
   after the licence lands, which is `docker restart <container>`.
3. **Step 2 is a real gap in the earlier design.** Once a licence is active DSS
   requires a login, so a known admin password is the fallback if the API-key
   path fails. It was missing from this document until Tim raised it.

`dssadmin set-license-file` is likely preferable to copying the file, because it
should validate and reload rather than requiring a restart — but its existence
and exact spelling are **unconfirmed for the versions in range**, and Tim notes
they vary by version.

**These are hypotheses.** The moment a container is running, enumerate the real
surface rather than guessing:

```bash
docker exec <container> /home/dataiku/dss/bin/dsscli --help
docker exec <container> /home/dataiku/dss/bin/dssadmin --help
```

Record the answers per era in `docs/findings/`. Command availability differing
across DSS 11/12/13/14/15 is exactly the kind of thing that silently breaks
provisioning for one line only.

## Step 3 — licence

Verified mechanism: DSS reads its licence from `DATA_DIR/config/license.json`.
Dropping a file there and restarting is sufficient, and works identically across
every version in range. `installer.sh -l <file>` is the alternative at first
install.

```bash
docker cp <licence> <container>:/home/dataiku/dss/config/license.json
# then restart DSS inside the container
```

**Licence source** is an untracked folder, currently
`~/Downloads/yournewinternalusagelicense/`. It must stay configurable and must
never be committed. Default via `DSS_LAB_LICENSE_DIR`.

### Choosing "the appropriate licence"

The five available licences differ by **feature tier, not DSS version**:

| Order | File | `standardOffer` / limits |
| --- | --- | --- |
| **1** | **`dev-*-2024.json`** | `enterprise-fy2023-1` |
| 2 | `dev-*-2025-enterprise.json` | `enterprise-ai-fy2025-1` |
| 3 | `dev-*-2025-aiml.json` | `ai-ml-fy2025-1` |
| 4 | `dev-*-2025-analytics.json` | `data-analytics-fy2025-1` |
| 5 | `dev-*-2018.json` | `licenseLimitsVersion: SAER`, govern features |

All five share `licenseKind: DATAIKU_INTERNAL`, `instanceId: devl1-timhonker`,
and **`expiresOn: 20260929`**.

**Try `dev-*-2024.json` first** (user direction, 2026-09-03), falling back down
the order above if DSS rejects it. The consumer targets *older* DSS versions, and
a 2024-era licence carrying an `fy2023` offer string is likelier to be understood
by DSS 12.x than a 2025 offer — so this ordering is also the one most likely to
work on the first attempt.

Match the files by **glob, not by exact name** — the `timhonker` portion is
specific to this user's licence set and should not be hard-coded.

An explicit `--license <file>` always overrides the order. Selection is never
silent: the chosen file appears in the output.

> Two unknowns here, both in [KNOWN_ISSUES](KNOWN_ISSUES.md): which offer
> strings an older DSS actually accepts (K10 — the 2024-first ordering is a
> hypothesis to confirm, not a settled fact), and whether DSS enforces the
> licence's `instanceId` against its own (K11). Both are cheap to settle once a
> container boots, and both can break the whole flow.
>
> Because a rejected licence is expected rather than exceptional, `provision`
> should **walk the order until one is accepted** rather than failing on the
> first rejection, and report which one won.

## Step 4 — admin API key

Verified mechanism: `dsscli api-key-create` runs from the data directory, needs
**no authentication** because it executes with filesystem access as the DSS
system user, and can emit JSON.

```bash
docker exec <container> /home/dataiku/dss/bin/dsscli api-key-create \
    --admin true --label dss-mac-docker --description "provisioned" \
    --output json --no-header
```

This resolves the bootstrap problem: once a licence is active DSS only accepts
username/password or CLI login, and `dsscli` is the CLI path. `--admin true` is
the highest global permission; the other `--may-*` flags are subsets and are not
needed.

The key is a credential. It goes into the JSON output and into
`~/.dataiku/config.json`, and **must never be logged, echoed to the terminal, or
committed**.

## Step 5 — register the instance

`dataiku-headless` reads `~/.dataiku/config.json`:

```json
{
  "default_instance": "<name>",
  "dss_instances": {
    "<nickname>": {
      "url": "http://localhost:11310",
      "api_key": "...",
      "no_check_certificate": false,
      "description": "DSS 12.3.1 (dss-mac-docker)"
    }
  }
}
```

Registering there means the caller only needs the **nickname** — it can
`switch_instance` and go, with no credential passed between agents.

> **That file already holds live API keys for the user's real instances**,
> including production. Writes must read-modify-write the `dss_instances` map,
> touch only our own key, and back the file up first. Never rewrite it wholesale
> and never change `default_instance` without being asked. See K12.

Nickname is `dss-<version>`, matching the container name so the two are
obviously the same thing.

## Idempotency

`provision` is safe to call repeatedly. An already-provisioned, already-running
version returns its existing connection details unchanged. A stopped one is
started. A missing API key is re-minted; an existing valid one is reused, since
`dsscli api-key-create` would otherwise mint a new key on every call.
