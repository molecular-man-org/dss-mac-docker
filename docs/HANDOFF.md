# Handoff — resume point

**Read this first.** Written to survive context-window compaction. If you have
no memory of this project, this file plus [RESEARCH.md](RESEARCH.md) is
everything you need.

Last updated: 2026-09-03 (v0.1.0)

---

## Where things stand

**Phases 1-4 are complete and verified against live containers. The repo now
does what it exists to do.**

The coding gate was lifted on 2026-09-03 ("resume work using
@dss-mac-docker/docs/HANDOFF.md"); no further permission is needed to continue.

Working today:

```bash
dss-lab doctor [--deep]     # preflight; --deep runs a real amd64 container
dss-lab catalog [--all]     # 109 versions, which are pull vs build
dss-lab resolve <spec>      # "DSS v12.3" -> 12.3.2
dss-lab info <spec>         # every derived name, port and image for a version
dss-lab versions
```

`tests/run_tests.sh` — 78 assertions, no Docker needed, mutation-tested to
confirm it actually catches regressions. shellcheck-clean at `-S warning`.

Lifecycle works: `up` / `ls` / `stop` / `url` / `logs` / `shell` / `rm` / `gc`,
plus `build` for the ~95 versions Hub does not publish. The three skills are
installed via `make install`.

Two instances run side by side and both were licensed and issued working admin
API keys — the whole provisioning chain, proven, on a pulled image and a built
one:

```text
12.6.4   dss-12.6.4   running   11640   pull    http://localhost:11640
12.6.7   dss-12.6.7   running   11670   build   http://localhost:11670
```

Findings: [provisioning chain](findings/provisioning-chain-verified.md) ·
[built image](findings/built-image-verified.md) ·
[readiness](findings/readiness-must-probe-the-backend.md)

`provision <spec> --output json` returns `{nickname, url, api_key, ...}`
unattended, and **`dataiku-headless` connected to a provisioned instance by
nickname alone**.

Verified end to end on **11.2.0** and **12.6.4** (pull), and **12.6.7**,
**13.5.7**, **14.7.3** (build) — all four release eras, both paths. **15.x is
the only unexercised line.**

Only `snapshot` / `restore` / `upgrade` (phase 5) and seed content (phase 7,
research only) remain.

## What this project is

A macOS + Docker Desktop toolkit for running **any DSS version from 11.0.0 to
15.0.0** (109 versions).

**Its primary consumer is another Claude project, not a human**:
`~/source_code/dataiku-upgrade-planning/dss-headless-upgrade-planning-skill`
tests its compatibility matrix against older DSS versions and calls this repo to
provision them — pull or start the container, apply a licence, mint an admin API
key, and hand back `{url, api_key, nickname}`. See
**[PROVISIONING.md](PROVISIONING.md)**, which is the contract that matters most.

`/start-dss-container 12.3.0` is the human-facing veneer over the same path.

## Decisions already made — do not relitigate

| Decision | Choice | Where |
| --- | --- | --- |
| Repo location | `molecular-man-org/dss-mac-docker`, **private** | user chose |
| Image sourcing | Hub first, build-from-kit fallback | user chose |
| Workflows in scope | all four: throwaway spins, side-by-side, upgrade testing, customer repro | user chose |
| Version range | **11.0.0+** — 12+ required, 11.x nice-to-have, nothing older | user chose |
| Instances per version | **exactly one**; version is the identity | user chose |
| `up` behaviour | idempotent, **never prompts**; existing container just starts | user chose |
| Naming | `dss-<version>` / `dss-<version>-data` / derived port | DESIGN D1 |
| State | Docker labels only, no state file | DESIGN D2 |
| Datadir | named volumes only, never macOS bind mounts | DESIGN D5 |
| `base_dss` tarballs | out of scope | RESEARCH §5 |
| Primary interface | machine-to-machine `provision`, JSON out | user, 2026-09-03 |
| Licence order | `dev-*-2024.json` **first**, then fall back | user, 2026-09-03 |
| Agent handoff | register in `~/.dataiku/config.json`, pass a nickname | DESIGN D8 |

## The two findings that shaped everything

1. **Docker Hub covers only 14 of 109 in-range versions (13%).** Every line's
   newest patch is missing. Build-from-kit is therefore the *primary* path, and
   the two-stage build (DESIGN D3) is load-bearing.
2. **The Docker VM has 6.25 GB RAM** on a 16 GB arm64 host, and DSS is x86-64
   only so everything runs emulated. This is the binding constraint on
   side-by-side use.

## Next actions

1. **Seed content** (phase 7, research only, Tim's item). A provisioned
   instance is empty and therefore a weak upgrade-test target. Start with the
   sibling `../dataiku-upgrade-planning/dss_project_*` repos, which look like
   exported DSS projects, before chasing internal Ansible repos.
2. **15.x** is the only unexercised line (`15.0.0`, pull path).
3. Phase 5 (`snapshot` / `restore` / `upgrade`) only if upgrade-path testing is
   still wanted; the consumer does not need it.

**Licences expire 2026-09-29.** After that, provisioning fails for every version
at once (K13).

## What two bugs here have in common

Both the readiness race and the masked-API-key bug had the same shape: **a step
reported success while producing something unusable**, and only a second,
differently-timed run exposed it. `provision` exited 0 in both cases.

For a machine-to-machine interface, well-formed output and a zero exit are not
evidence of a working result. Verify the artefact by using it — which is why
readiness probes the backend rather than nginx, and why an API key is confirmed
with a live call rather than trusted from a listing.

## Traps that will cost you time

- **`run.sh` migrates datadirs irreversibly and silently** when the version
  differs. The guard is not optional and must land with `up`, not after. See
  KNOWN_ISSUES K3.
- **Every docker call needs `--platform linux/amd64`.** arm64 host, x86-64-only
  product.
- **`dsscli` talks to the DSS backend over REST, not the filesystem.** Every
  subcommand needs the backend up on `:10001`. nginx serves the login page ~10s
  earlier, so anything that treats `GET /` as readiness will intermittently fail
  under automation. This bit once already —
  [finding](findings/readiness-must-probe-the-backend.md).
- **Do not move the version ARG above the expensive layers** in the era
  Dockerfiles. That is the upstream bug being fixed. RESEARCH §8.
- The user works evidence-first: measure, then assert. Their sibling repo
  `../dss-ssh-triage` sets the house style — `bin/` + `bin/lib/common.sh`,
  `Makefile`, `docs/` with findings and runbooks, `tests/run_tests.sh`.

## Verify-before-trusting

Marked **UNVERIFIED** in KNOWN_ISSUES: symlinked skills (K6), DSS actually
booting under Rosetta (K2), Java 8 recipe against late 12.x (K7), `base_dss`
semantics (K8), licence offer-string compatibility (K10), licence `instanceId`
binding (K11).

Two hazards that are *verified* and dangerous rather than merely unknown:

- **K12** — `~/.dataiku/config.json` holds the user's live production API keys.
  Merge into it; never rewrite it.
- **K13** — every available licence expires **2026-09-29**. After that,
  provisioning breaks for every version at once.

Mechanisms that are **confirmed** and need no further research: licence goes to
`DATA_DIR/config/license.json`; `dsscli api-key-create --admin true --output
json` needs no prior credential; `dataiku-headless` reads `url` / `api_key` /
nickname from `~/.dataiku/config.json`.
