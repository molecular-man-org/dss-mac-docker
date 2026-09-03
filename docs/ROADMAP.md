# Roadmap

Six phases. Phase 2 is the first point where the tool is usable at all; phase 3
unlocks the ~95 versions that are not on Docker Hub; **phase 4 is the point of
the repo** — the machine-to-machine provisioning contract the sibling
upgrade-planning project depends on.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done and verified

---

## Phase 1 — Foundation `[x] complete 2026-09-03`

- [x] `bin/lib/common.sh` — logging, error handling, version parsing, port formula
      (+ canonicality guard), era mapping, derived identities, VM probing.
      `--platform linux/amd64` is applied explicitly by the commands that create
      or fetch images, **not** by a blanket wrapper — it breaks `ps`/`logs`.
- [x] `bin/dss-lab doctor` — daemon running (offer `open -a Docker`), Rosetta
      enabled, VM RAM/disk headroom, `--platform` support
- [x] `bin/dss-lab catalog` — merge `data/versions-11plus.txt` with live Hub tags,
      label each `pull` or `build`; cache the Hub query
- [x] `bin/dss-lab resolve <spec>` — `v12.3.0` / `12.3` / `13` / `latest` → concrete
- [x] `tests/run_tests.sh` — unit tests for parsing, port formula, resolution.
      No Docker required. **78 assertions, mutation-tested.**

Also delivered: `dss-lab info <spec>` (everything derived from a version) and
`dss-lab versions`. shellcheck-clean at `-S warning`.

> Verified: `doctor` exercised against a live daemon in both states, and
> `doctor --deep` confirmed amd64 emulation actually executes. See
> [findings/rosetta-amd64-verified.md](findings/rosetta-amd64-verified.md).

## Phase 2 — Usable end to end `[x] complete 2026-09-03`

- [x] `up` with the idempotent state machine (DESIGN D4) **and the K3 migration
      guard in the same change**
- [x] `ls`, `stop`, `logs`, `shell`, `url`, `rm`, `gc`
- [x] `wait` — HTTP readiness poll, long first-boot timeout
- [ ] Memory profile written to `env-site.sh` at first boot; **measure the right
      heap on a live instance rather than guessing** (DESIGN D7)
- [x] `skills/{start,stop}-dss-container/SKILL.md`, `skills/list-dss-containers/SKILL.md`
- [x] `Makefile` `install` / `uninstall` targets; K6 resolved by copy+substitute
- [x] Verified against Hub's `12.6.4` (Tim's chosen example) — booted in ~50s,
      HTTP 200, supervisord backend/ipython/nginx all RUNNING

> Exit criterion: `/start-dss-container 14.4.1` works from a cold start, and
> running it twice is a no-op that returns the URL.

## Phase 3 — All 109 versions `[x] complete 2026-09-03`

- [x] `docker/Dockerfile.kit` — **one** parameterised Dockerfile, not three.
      Deriving from a Hub era base means the era only selects `BASE_IMAGE` and
      `PUPPETEER_VERSION`, so per-era files are needed solely for a
      from-scratch build. ARG is declared below the base, fixing RESEARCH §8.
- [ ] `docker/Dockerfile.dss11-12`, `.dss13`, `.dss14-15` — only for
      `--era-base scratch`; deferred until something actually needs it
- [ ] `build <version>` with era detection and era-base resolution (DESIGN D3)
- [ ] `--era-base scratch` clean-build option (deferred; nothing needs it yet)
- [x] Verified on `12.6.7` — builds, boots in 35s, reports
      `product_version: 12.6.7`, and licenses + provisions identically to a
      pulled image ([finding](findings/built-image-verified.md))
- [ ] Still to verify per era: `13.5.7` and `14.7.3` (14.x/15.x untested;
      also resolves K7 for late 12.x)

## Phase 4 — Provisioning (the point of the repo)

Serves [PROVISIONING.md](PROVISIONING.md). Promoted above upgrade paths because
the sibling project depends on it.

- [ ] `license <version>` — walk the preference order (`dev-*-2024.json` first),
      `docker cp` into `config/license.json`, restart, verify DSS accepted it
- [ ] Expiry pre-check — fail loudly rather than let DSS report it obliquely (K13)
- [ ] `apikey <version>` — `dsscli api-key-create --admin true --output json`;
      reuse an existing key rather than minting a duplicate
- [ ] `register <version>` — merge-safe write into `~/.dataiku/config.json`,
      with a backup first (K12)
- [ ] `provision <spec> [--output json]` — the whole flow end to end
- [ ] Settle K11 (licence `instanceId` binding) at the first booted container

> Exit criterion: the upgrade-planning skill asks for DSS 12.3.1 and gets back a
> working `{url, api_key, nickname}` without a human touching anything.

## Phase 5 — Upgrade paths

- [ ] `snapshot` / `restore` — volume clone
- [ ] `upgrade <from-version> <to-version>` — snapshot, then let `run.sh` migrate
- [ ] Verified on a real 13.x → 14.x migration

## Phase 6 — Evidence

- [ ] `bundle <version> <file>` — preload a project bundle
- [ ] `docs/compatibility-matrix.md` — boot each era under Rosetta, record results
      in `evidence/`; covers K2 and the boundary versions
