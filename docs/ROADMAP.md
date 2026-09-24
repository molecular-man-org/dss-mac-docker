# Roadmap

Eight phases. Phase 2 is the first point where the tool is usable at all;
phase 3 unlocks the ~95 versions that are not on Docker Hub; **phase 4 is the
point of the repo** — the machine-to-machine provisioning contract the sibling
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
      No Docker required. Mutation-tested. (167 assertions as of v0.1.0;
      78 when phase 1 closed.)

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
- [x] Memory profile — **measured and deliberately not implemented** (DESIGN D7):
      idle 1.9-2.5 GiB from 12.x to 15.x, and DSS's own JVM heaps are already
      capped at 2 GiB, so there is nothing to tune
- [x] `skills/{start,stop}-dss-container/SKILL.md`, `skills/list-dss-containers/SKILL.md`
- [x] `Makefile` `install` / `uninstall` targets; K6 resolved by copy+substitute
- [x] Verified against Hub's `12.6.4` (Tim's chosen example) — booted in ~50s,
      HTTP 200, supervisord backend/ipython/nginx all RUNNING

> Exit criterion **met, 2026-09-23**: `14.4.1` from a cold start (image pull and
> first boot) answered HTTP 200 in 143s; a second `up` returned in 1s with "already
> running", the same URL and still one container. Run through `dss-lab up`, which
> the `start-dss-container` skill wraps.

## Phase 3 — All 109 versions `[x] complete 2026-09-03`

- [x] `docker/Dockerfile.kit` — **one** parameterised Dockerfile, not three.
      Deriving from a Hub era base means the era only selects `BASE_IMAGE` and
      `PUPPETEER_VERSION`, so per-era files are needed solely for a
      from-scratch build. ARG is declared below the base, fixing RESEARCH §8.
- [x] `docker/Dockerfile.dss11-12`, `.dss13`, `.dss14-15` — **decided against**:
      they exist only for `--era-base scratch`, which is below
- [x] `build <version>` with era detection and era-base resolution (DESIGN D3)
- [x] `--era-base scratch` — **decided against, 2026-09-23.** A from-scratch build
      costs about an hour of emulated R compilation per era, nothing needs it,
      and it could not be verified without those hours. Building on the nearest
      Hub image reaches every catalogue version (DESIGN D3). The flag stays
      rejected with an explanation. Reopen only if Hub stops publishing bases.
- [x] Verified on `12.6.7` — builds, boots in 35s, reports
      `product_version: 12.6.7`, and licenses + provisions identically to a
      pulled image ([finding](findings/built-image-verified.md))
- [x] Verified per era by build: `12.4.2`, `13.5.7` and `14.7.3` boot, license and
      provision; 15.x runs from its Hub image ([matrix](compatibility-matrix.md)).
      This also resolves K7 for late 12.x.

## Phase 4 — Provisioning (the point of the repo) `[x] complete 2026-09-03`

Serves [PROVISIONING.md](PROVISIONING.md). Promoted above upgrade paths because
the sibling project depends on it.

- [x] `license <version>` — walks the preference order (`dev-*-2024.json` first),
      `docker cp` into `config/license.json`, restart, verify DSS accepted it
- [x] Expiry pre-check — fail loudly rather than let DSS report it obliquely (K13)
- [x] `apikey <version>` — `dsscli api-key-create --admin true --output json`;
      reuse an existing key rather than minting a duplicate
- [x] `register <version>` — merge-safe write into `~/.dataiku/config.json`,
      with a backup first (K12)
- [x] `provision <spec> [--output json]` — the whole flow end to end
- [x] K11 settled — `instanceId` does not block licence application

> Exit criterion **met**: `provision 12.6.7 --output json` returns a working
> `{url, api_key, nickname}` unattended, and `dataiku-headless` connected to it
> by nickname alone —
> [finding](findings/provisioning-flow-verified.md).

## Phase 5 — Upgrade paths `[x] complete 2026-09-23`

- [x] `snapshot` / `restore` — volume clone; `restore` demands `--force`
- [x] `upgrade <from> <to>` — clones the datadir and lets `run.sh` migrate the
      clone; the source is left untouched as the rollback (DESIGN D5)
- [x] Verified on real migrations 12.6.4 → 13.4.4 → 14.7.0 → 15.0.0
      ([matrix](compatibility-matrix.md))

## Phase 6 — Evidence `[x] complete 2026-09-23`

- [x] `bundle <version> <file.zip>` — imports a project export archive; verified
      live, including newer-into-older (15.0.0 archive into 12.6.4)
- [x] `docs/compatibility-matrix.md` — licence tiers, boot and upgrade results
      measured on real containers; first pass, boundaries and every era

## Phase 8 — Route registration as a gate screen `[ ] HYPOTHESIS`

Test whether REST route registration predicts capability-gate errors defined at
the MCP layer. If it holds it is a fast triage for ~10 unverified gates; if it
over-reports, its false-positive rate is still worth knowing.

Full reasoning and the first data point in
[findings/v12-vs-v14-object-availability.md](findings/v12-vs-v14-object-availability.md).

- [ ] Resolve the two wrong-URL rows first — a screen built on guessed paths
      would industrialise the false-negative it is meant to catch
- [ ] Get the Knowledge Banks outcome at the MCP layer from the consumer
- [ ] Only then decide whether to build probes around it

## Phase 7 — Seed content for provisioned instances `[ ] RESEARCH ONLY`

> **Do not implement yet.** Tim raised this 2026-09-03 as a research item.

A freshly provisioned instance is **empty**, which makes it a poor test target:
the upgrade-planning skill needs projects, flows, datasets and code envs present
to scan, test compatibility against, and upgrade. An empty DSS exercises almost
none of what its matrix checks.

Research needed, in rough order of promise:

1. **Ansible roles** for controlling and configuring DSS nodes. **Needs a
   pointer**: repo names or URLs. Not investigated, because guessing at repo
   names is not research.
2. **Project bundles.** Already reachable from the confirmed `dsscli` surface —
   `project-import`, `project-export`, `bundle-export`,
   `bundle-download-archive`. This is the lowest-friction path and needs no
   external repo: export a representative project once, import it at provision
   time.
3. **The sibling repos already on this machine** —
   exported DSS projects kept alongside the consumer project. Worth inspecting
   before reaching for anything external.
4. **Code envs.** `dsscli code-envs-list` / `code-env-update` exist, and code
   envs are a common upgrade-compatibility failure point, so seeded content
   probably needs at least one.

Open question for Tim: should seed content be **version-appropriate** (a project
exported from the same DSS line) or **deliberately old** (a 12.x-era project
imported into 14.x, which is what an upgrade actually looks like)? The second is
a better test and is probably the point.
