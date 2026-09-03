# Roadmap

Five phases. Phase 2 is the first point where the tool is usable at all; phase 3
is the first point where it is useful for its main purpose.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done and verified

---

## Phase 1 — Foundation

- [ ] `bin/lib/common.sh` — logging, error handling, `docker` wrapper that always
      passes `--platform linux/amd64`, version parsing, port formula (+ guard)
- [ ] `bin/dss-lab doctor` — daemon running (offer `open -a Docker`), Rosetta
      enabled, VM RAM/disk headroom, `--platform` support
- [ ] `bin/dss-lab catalog` — merge `data/versions-11plus.txt` with live Hub tags,
      label each `pull` or `build`; cache the Hub query
- [ ] `bin/dss-lab resolve <spec>` — `v12.3.0` / `12.3` / `13` / `latest` → concrete
- [ ] `tests/run_tests.sh` — unit tests for parsing, port formula, resolution.
      No Docker required.

## Phase 2 — Usable end to end

- [ ] `up` with the idempotent state machine (DESIGN D4) **and the K3 migration
      guard in the same change**
- [ ] `ls`, `stop`, `logs`, `shell`, `url`, `rm`, `gc`
- [ ] `wait` — HTTP readiness poll, long first-boot timeout
- [ ] Memory profile written to `env-site.sh` at first boot; **measure the right
      heap on a live instance rather than guessing** (DESIGN D7)
- [ ] `skills/{start,stop}-dss-container/SKILL.md`, `skills/list-dss-containers/SKILL.md`
- [ ] `Makefile` `install` / `uninstall` targets; resolve K6
- [ ] Verified against Hub's `14.4.1`

> Exit criterion: `/start-dss-container 14.4.1` works from a cold start, and
> running it twice is a no-op that returns the URL.

## Phase 3 — All 109 versions

- [ ] `docker/Dockerfile.dss11-12`, `.dss13`, `.dss14-15` — transcribed from the
      upstream commits in RESEARCH §6, ARG moved below the expensive layers
- [ ] `build <version>` with era detection and era-base resolution (DESIGN D3)
- [ ] `--era-base scratch` clean-build option
- [ ] Verified on a non-Hub version per era — suggest `12.6.7`, `13.5.7`, `14.7.3`
      (also resolves K7)

## Phase 4 — Upgrade paths

- [ ] `snapshot` / `restore` — volume clone
- [ ] `upgrade <from-version> <to-version>` — snapshot, then let `run.sh` migrate
- [ ] Verified on a real 13.x → 14.x migration

## Phase 5 — Customer repro and evidence

- [ ] `license <version> <file>` — inject an enterprise licence
- [ ] `bundle <version> <file>` — preload a project bundle
- [ ] `docs/compatibility-matrix.md` — boot each era under Rosetta, record results
      in `evidence/`; covers K2 and the boundary versions
