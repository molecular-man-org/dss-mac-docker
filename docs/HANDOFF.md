# Handoff — resume point

**Read this first.** Written to survive context-window compaction. If you have
no memory of this project, this file plus [RESEARCH.md](RESEARCH.md) is
everything you need.

Last updated: 2026-09-03 (phase 1 complete; provisioning direction added)

---

## Where things stand

**Phase 1 is complete and verified. Phase 2 has not started.**

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

Every phase-2+ subcommand (`up`, `ls`, `build`, ...) is dispatched but exits
with "not implemented yet".

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

**Phase 2** per [ROADMAP.md](ROADMAP.md), in this order:

1. `up` — the idempotent state machine (DESIGN D4) **with the K3 migration guard
   in the same change, not after**. Uses `catalog_source` to decide pull vs
   build; build itself can stub out to phase 3 initially so `up` can be proven
   against a Hub version first.
2. `ls`, `stop`, `logs`, `shell`, `url`, `rm`, `gc` — all read state from Docker
   labels, never a state file (DESIGN D2).
3. `wait` — HTTP readiness poll. First boot is slow under emulation; start the
   timeout at 30 minutes.
4. Memory profile into `env-site.sh` at first boot — **measure the heap on a
   live instance rather than guessing** (DESIGN D7).
5. The three skills + `make install`; resolve K6 (symlink vs copy).

Exit criterion: `/start-dss-container 14.4.1` works cold, and re-running is a
no-op that returns the URL.

Good first target is `14.4.1` — it is on Hub, so phase 2 needs no build path.

**Settle K11 the moment the first container boots**: the licences carry
`instanceId: devl1-timhonker`, and if DSS enforces that, the whole provisioning
flow dies at step 3. It is a two-minute check that can invalidate the design, so
do it before building anything on top.

Phase 3 (build) is on the critical path for the real consumer — the example the
user gave, DSS 12.3.1, is **not** on Docker Hub.

## Traps that will cost you time

- **`run.sh` migrates datadirs irreversibly and silently** when the version
  differs. The guard is not optional and must land with `up`, not after. See
  KNOWN_ISSUES K3.
- **Every docker call needs `--platform linux/amd64`.** arm64 host, x86-64-only
  product.
- **Nothing has yet pulled, built or run a DSS image.** `doctor` has been
  exercised against a live daemon and amd64 emulation is proven
  ([finding](findings/rosetta-amd64-verified.md)), but the first `up` is still a
  bring-up. See K9.
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
