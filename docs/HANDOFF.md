# Handoff — resume point

**Read this first.** Written to survive context-window compaction. If you have
no memory of this project, this file plus [RESEARCH.md](RESEARCH.md) is
everything you need.

Last updated: 2026-09-03 (phases 1-3 complete)

---

## Where things stand

**Phases 1, 2 and 3 are complete and verified against live containers.**

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

Only `provision` / `license` / `apikey` / `register` / `snapshot` / `restore` /
`upgrade` remain unimplemented — the phase-4 wrappers around mechanisms that are
now all confirmed to work.

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

**Phase 4 — provisioning** per [ROADMAP.md](ROADMAP.md). Every underlying
mechanism is now confirmed working by hand; phase 4 is wrapping them:

1. `license <version>` — walk the preference order (`dev-*-2024.json` first),
   `docker cp` then `dsscli set-license <path>`, check expiry first (K13)
2. `apikey <version>` — `dsscli api-key-create --admin true --output json`;
   reuse an existing key via `api-keys-list` rather than minting duplicates
3. `register <version>` — **merge** into `~/.dataiku/config.json`, back it up
   first; that file holds live production credentials (K12)
4. `provision <spec> --output json` — the whole flow, emitting
   `{nickname, url, api_key}`

Then phase 3's remaining verification: build and boot one **13.x** and one
**14.x** version. Only the 12.x era has been exercised, and 14/15 differ in base
OS, Java and Python.

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
