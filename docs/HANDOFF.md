# Handoff — resume point

**Read this first.** Written to survive context-window compaction. If you have
no memory of this project, this file plus [RESEARCH.md](RESEARCH.md) is
everything you need.

Last updated: 2026-09-03

---

## Where things stand

**Planning and research are complete and signed off. No implementation code
exists yet.** The repo currently contains documentation, two research data files,
and empty scaffolding directories.

The user (Tim, `THE-MOLECULAR-MAN`) gated implementation with "plan first, do not
write code yet" and has **not yet lifted that gate**. The last instruction was to
create the repo and document everything — which is what exists now.

> **Do not start writing `bin/dss-lab` without confirming.** Ask whether to begin
> phase 1-2. Everything needed to start immediately is in ROADMAP.md.

## What this project is

A macOS + Docker Desktop toolkit for running **any DSS version from 11.0.0 to
15.0.0** (109 versions), driven by a Claude Code skill so the user can type
`/start-dss-container 12.3.0` or "create a new instance of DSS v12.3.0".

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

## The two findings that shaped everything

1. **Docker Hub covers only 14 of 109 in-range versions (13%).** Every line's
   newest patch is missing. Build-from-kit is therefore the *primary* path, and
   the two-stage build (DESIGN D3) is load-bearing.
2. **The Docker VM has 6.25 GB RAM** on a 16 GB arm64 host, and DSS is x86-64
   only so everything runs emulated. This is the binding constraint on
   side-by-side use.

## Next actions

1. Confirm with the user that implementation can begin.
2. Phase 1 per [ROADMAP.md](ROADMAP.md) — `common.sh`, `doctor`, `catalog`,
   `resolve`, unit tests. None of it needs a running Docker daemon.
3. Phase 2 — `up` **with the K3 migration guard in the same change**, plus the
   three skills and `make install`. Exit criterion: `/start-dss-container 14.4.1`
   works cold, and re-running is a no-op returning the URL.

## Traps that will cost you time

- **`run.sh` migrates datadirs irreversibly and silently** when the version
  differs. The guard is not optional and must land with `up`, not after. See
  KNOWN_ISSUES K3.
- **Every docker call needs `--platform linux/amd64`.** arm64 host, x86-64-only
  product.
- **No Docker command in this repo has run against a live daemon.** The daemon
  was down during research; everything is written from the documented contract.
  Treat first execution as bring-up. See K9.
- **Do not move the version ARG above the expensive layers** in the era
  Dockerfiles. That is the upstream bug being fixed. RESEARCH §8.
- The user works evidence-first: measure, then assert. Their sibling repo
  `../dss-ssh-triage` sets the house style — `bin/` + `bin/lib/common.sh`,
  `Makefile`, `docs/` with findings and runbooks, `tests/run_tests.sh`.

## Verify-before-trusting

Marked **UNVERIFIED** in KNOWN_ISSUES: symlinked skills (K6), Rosetta boot per
era (K2), Java 8 recipe against late 12.x (K7), `base_dss` semantics (K8).
