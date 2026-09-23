# Provisioning contract

**This is the repo's primary interface.** The main consumer is not a human but
another Claude project, an upgrade-planning skill, which tests its
compatibility matrix against a range of older DSS versions and needs them
provisioned on demand.

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
  "licence": "dev-example-2024.json",
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

Tim then supplied the **real command surface** from a live DSS instance, which
settles most of it — see "Verified CLI surface" below.

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

## Verified CLI surface

From a live DSS instance (Tim, 2026-09-03). This replaces the guesses above.

**`dssadmin` has no licence action.** Its actions are integrations
(`install-R-integration`, `install-spark-integration`, …), `build-base-image`,
`regenerate-config`, `encrypt-password`, `run-diagnosis`,
`verify-installation-integrity`. So `dssadmin set-license-file` **does not
exist** — that guess was wrong.

**`dsscli` is the tool for all three provisioning steps:**

| Need | Command |
| --- | --- |
| Apply licence (step 3) | `dsscli set-license` |
| Admin password (step 2) | `dsscli user-edit` |
| API key (step 4) | `dsscli api-key-create` |
| Check existing keys (idempotency) | `dsscli api-keys-list` |
| Reload after config change | `dsscli config-cache-invalidate` |

Also available and useful later: `user-create`, `groups-list`, `project-import`,
`bundle-export` (phase 6 bundle preloading).

Still to confirm, because `--help` output at this level does not show them:

- exact flags for `dsscli set-license` (file path as positional, or a flag?)
- exact flags for `dsscli user-edit` to set a password — and whether it wants a
  cleartext password or one hashed by `dssadmin encrypt-password`
- whether `set-license` reloads on its own or still needs a restart

Enumerate per version rather than assuming, since Tim notes the commands vary:

```bash
docker exec <container> /home/dataiku/dss/bin/dsscli set-license -h
docker exec <container> /home/dataiku/dss/bin/dsscli api-key-create -h
docker exec <container> /home/dataiku/dss/bin/dsscli user-edit -h
```

> The paste came from a manual install (`dss_data`, argparse "optional
> arguments" — so Python < 3.10, an older DSS). Confirm the same surface exists
> on each era in range; a command present in 12.x but renamed in 15.x would break
> provisioning for one line only. Record results in `docs/findings/`.

## Step 3 — licence

**What `license_apply` actually does** — one route, not two:

```bash
docker cp <licence> <container>:/tmp/dss-lab-license.json
docker exec <container> /home/dataiku/dss/bin/dsscli set-license /tmp/dss-lab-license.json
docker exec <container> rm -f /tmp/dss-lab-license.json
```

`dsscli set-license` writes `DATA_DIR/config/license.json` itself and takes
effect **without a restart**. The staging copy is removed afterwards so a licence
does not linger in `/tmp` inside the container.

> `dsscli` is a **REST client against the DSS backend on `:10001`**, not a
> filesystem tool, so this only works once the backend is genuinely up. That is
> why readiness probes the API rather than nginx — see
> [findings/readiness-must-probe-the-backend.md](findings/readiness-must-probe-the-backend.md).

Writing `config/license.json` directly and restarting also works and needs no
running backend, and `installer.sh -l <file>` applies one at first install.
**Neither is implemented** — they are documented as escape hatches if
`dsscli set-license` ever proves unavailable on some version.

**Licence source** is an untracked folder of licence files you supply,
defaulting to `~/.dss-lab/licences/`. It must stay configurable and must never
be committed. Override with `DSS_LAB_LICENSE_DIR`.

### Choosing "the appropriate licence"

The licences you supply differ by **feature tier, not DSS version**. `provision`
walks these filename globs in order and applies the first file DSS accepts:

| Order | Glob |
| --- | --- |
| **1** | **`dev-*-2024.json`** |
| 2 | `dev-*-2025-enterprise.json` |
| 3 | `dev-*-2025-aiml.json` |
| 4 | `dev-*-2025-analytics.json` |
| 5 | `dev-*-2018.json` |

The globs follow one licence set's naming convention; edit `LICENSE_GLOBS` in
`bin/lib/provision.sh` to match yours.

Each licence names an `instanceId` and an `expiresOn`; neither blocks
application to a fresh container (see K11).

**Try the 2024 licence first**, falling back down the order above if DSS rejects
it. The consumer targets *older* DSS versions, and an older offer string is
likelier to be understood by DSS 12.x than a 2025 one — so this ordering is
also the one most likely to work on the first attempt.

Match the files by **glob, not by exact name** — the user portion of the
filename is specific to one licence set and should not be hard-coded.

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
