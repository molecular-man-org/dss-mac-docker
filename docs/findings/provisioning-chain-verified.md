# The provisioning chain works end to end on DSS 12.6.4

**Date:** 2026-09-03
**Status:** verified against a live container
**Closes:** [KNOWN_ISSUES](../KNOWN_ISSUES.md) K11 · settles the phase-4 command surface

Every step of [PROVISIONING.md](../PROVISIONING.md) was executed against a real
`dss-12.6.4` container. Nothing below is inferred.

## 1. First boot is about a minute, not "ten minutes or more"

> **Corrected 2026-09-03** by
> [readiness-must-probe-the-backend](readiness-must-probe-the-backend.md). The
> "HTTP 200 at 25s" below was **nginx**, not DSS. The readiness probe used at the
> time reported success while the backend was still starting. Real
> backend-ready is ~50-60s. The order of magnitude stands; the figure was
> optimistic.

The design assumed first boot would be slow because `installer.sh`, R integration
and graphics export all run under Rosetta. Measured: HTTP 200 at 25 seconds
(nginx), with `supervisord` reporting `backend`, `ipython` and `nginx` all
`RUNNING` by ~50s.

The reason, as Tim pointed out: **the Hub images ship DSS already installed**,
R packages included. `run.sh` only initialises the datadir, which is mostly file
copying. The expensive emulated work was done at image build time by Dataiku.

Corrected in the skill text, which told users to expect 10+ minutes.

> Caveat: this is the *pull* path on a 12.x image. A **built** image
> (`Dockerfile.kit`) installs a different kit at build time, and a 14.x/15.x
> first boot is unmeasured. Do not generalise the 50s figure yet.

## 2. `dssadmin` has no licence action — the earlier guess was wrong

`dssadmin` covers integrations (`install-R-integration`, `install-spark-integration`,
…), `build-base-image`, `regenerate-config`, `encrypt-password`, `run-diagnosis`,
`verify-installation-integrity`. There is **no `set-license-file`**.

## 3. `dsscli set-license` takes a positional path

```text
usage: dsscli set-license [-h] license_file
```

Confirmed identically on this 12.6.4 container and, independently, on Tim's own
instance.

```bash
docker cp <licence> dss-12.6.4:/tmp/license.json
docker exec dss-12.6.4 /home/dataiku/dss/bin/dsscli set-license /tmp/license.json
# exit 0; writes /home/dataiku/dss/config/license.json
```

It **succeeds while DSS is running** and needs no restart for the API to report
the new licence.

## 4. K11 resolved — `instanceId` does not block application

The licences carry `instanceId: devl1-timhonker`. This was the risk flagged as
able to invalidate the whole design. It does not: `dev-timhonker-2024.json`
applied cleanly to a container with no relationship to that instance id.

Confirmed active rather than merely present, via
`GET /public/api/admin/licensing/status`:

| Field | Value |
| --- | --- |
| `base.expiresOn` | `1790640000000` → **2026-09-29** |
| free/community edition | **False** |

The expiry matches the licence file's `expiresOn: 20260929` exactly, so it is
demonstrably *that* licence in force, not a default.

## 5. `dsscli api-key-create` mints a working admin key

```bash
docker exec dss-12.6.4 /home/dataiku/dss/bin/dsscli api-key-create \
    --admin true --label dss-mac-docker --description "..." --output json
```

Returns clean JSON — `{id, key, label, description}` — with a 32-character key.
No prior credential needed, which is the bootstrap the design depends on.

Proven to actually carry admin rights, not just authenticate:

| Request | Result |
| --- | --- |
| `GET /public/api/projects/` with the key | **200** |
| `GET /public/api/admin/licensing/status` with the key | **200**, returns data |
| same admin endpoint with **no** credentials | **401** |

Auth is HTTP basic with the key as the username and an empty password
(`curl -u "$KEY:"`).

## 6. Admin password, for the fallback path

`dsscli user-edit <login> --password <pw>` — positional login, `--password`
flag. So step 2 of Tim's sketch is `dsscli user-edit admin --password ...`.
Unverified whether it wants cleartext or a `dssadmin encrypt-password` hash;
cleartext is the natural reading of "New password".

## What remains unverified

- The same command surface on **13.x, 14.x and 15.x**. `dsscli` subcommand names
  have changed across DSS versions before; confirm per era before trusting.
- Whether a **built** (non-Hub) image behaves identically — see phase 3.
- Whether the other four licences apply as cleanly as the 2024 one.
