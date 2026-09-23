# Handoff — resume point

**Read this first.** Written to survive context-window compaction. If you have
no memory of this project, this file plus [RESEARCH.md](RESEARCH.md) is
everything you need.

Last updated: 2026-09-03 (v0.1.0 + seeding slices 1-3)

---

## RESUME HERE — era-appropriate content (paused 2026-09-11)

**Plan: [ERA_CONTENT_PLAN.md](ERA_CONTENT_PLAN.md) — final, not yet built.** Tim
closed the session asking for it to be resumable next week "and implement this
plan". Read that file first; this section only says where to start.

### Done before pausing

- **Step 0** — `dataiku-headless` connector updated 0.2.0 → **0.6.0** and verified
  in the running MCP processes (`.../dataiku-headless/0.6.0/runtime/run_mcp.py`).
  Re-check after any restart: `pgrep -fl 'dataiku-headless/0\.6\.0'`.
- **Phase A2** — licence × DSS-version matrix measured on 11.2.0, 12.6.7, 13.5.7,
  14.7.3. The measurements are kept locally and are not published here.
- **Decisions** — 2024 licence (`enterprise-fy2023-1`) on every node, admin pinned
  to `DESIGNER`; model export accepted as untestable; ~15 min seeding budget.
- **Seed projects** — Tim's five demo exports are kept
  outside the repo, in the directory named by `DSS_LAB_SEED_PROJECTS_DIR`.

### Start next session with

1. **Phase A1, repro first.** Start a node (`dss-lab up 14.7.3`) and confirm
   admin is demoted: stored `DATA_SCIENTIST`, absent from `base.userProfiles`.
   Record which admin actions fail — a job, a scenario, an import. That failure
   is the regression test.
2. Then implement A1 in `bin/lib/provision.sh`: the `set-license` read-back
   gate, `admin_profile_ensure` using the pin, and the `docker exec -u root`
   cleanup fix.
3. Then the **spike** (plan step 2). It includes importing
   `VFR_FLIGHT_WEATHER_PREDICTION` into a 12.x node: whether older DSS accepts
   a newer export decides Phase E's scope.

### State left behind

- **All six nodes stopped**, every one on the 2024 licence. Volumes, keys and seed
  slices 1-3 intact; each restarts in ~20s with `dss-lab up <version>`.
- `dss-12.4.2` was running when paused (probably the peer's Knowledge Banks work)
  and was stopped. Its admin was already on `DESIGNER` — not the install default;
  possibly changed by that session, unverified.
- A staged licence copy is still in `/tmp` inside 12.4.2 and 14.7.3 — the A1 cleanup
  bug. Harmless locally; A1 fixes it.
- `provision.sh` reads licences from `~/.dss-lab/licences` unless
  `DSS_LAB_LICENSE_DIR` is set.

### Rules that bind this work

- **Local Docker DSS nodes: change freely. Internet DSS nodes: never.** The
  connector's default instance may be an internet node —
  `switch_instance` to a local `dss-*` nickname before any connector call.
- The consumer project reviews the content mix before
  content is built (plan step 3), and directs seeding priorities.
- Max **two** DSS nodes running at once.

### Three bugs already found in shipped code, all fixed by A1

- `dsscli set-license` exits 0 for a licence the node cannot parse; licensing
  status then 400s — the endpoint readiness polls.
- `license_apply`'s cleanup `rm` fails as `dataiku` on a root-owned file and
  `|| true` hides it.
- `seed/dss_seed.py` `code_envs()` swallows errors into `[]` — the 403-as-absent
  shape.

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
The upgrade-planning skill
tests its compatibility matrix against older DSS versions and calls this repo to
provision them — pull or start the container, apply a licence, mint an admin API
key, and hand back `{url, api_key, nickname}`. See
**[PROVISIONING.md](PROVISIONING.md)**, which is the contract that matters most.

`/start-dss-container 12.3.0` is the human-facing veneer over the same path.

## Decisions already made — do not relitigate

| Decision | Choice | Where |
| --- | --- | --- |
| Repo location | `molecular-man-org/dss-mac-docker`, public | user chose |
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

1. **Finish slice 3's CustomCode recipe.** `cpython` is done; the CustomCode
   half is blocked on the recipe-creation body format, with all progress
   recorded in [SEEDING.md](SEEDING.md). The dev plugin is already installed and
   registered on `dss-14.7.3`; only the create call fails. **Do not guess enum
   values** — that was tried and wasted time.
2. **A 12.0.x or 12.2.x instance**, below the consumer's 12.3.0 LLM Mesh gate.
   That completes the bracket 12.4.2 half-opened, and 12.0.x is the baseline
   their v12 assertions are built on.
3. **Slices 4-7** in [SEEDING.md](SEEDING.md): lifecycle status, job/scenario
   recency, duplicate-family keys, tutorial prefixes.
4. **15.x** is the only unexercised DSS line (`15.0.0`, pull path).
5. Phase 5 (`snapshot` / `restore` / `upgrade`) only if wanted; the consumer
   does not need it.

## Open item from 2026-09-03 shutdown

`dss-11.2.0`, `dss-12.4.2` and `dss-13.5.7` last exited **137** (SIGKILL),
before the stop-timeout fix landed. They were going to be cycled — start, then
clean stop — to clear any stale lock state and confirm their datadirs still
start, but Docker Desktop was shut down first, so **the cycle never ran**.

Nothing is known to be wrong. The fix is in, so their *next* stop will be clean.
But they have not been started since being killed, so **if one of those three
fails to start in a way resembling corruption rather than configuration, this is
the first place to look** — not a mystery, a known unverified state.

The other three (`12.6.4`, `12.6.7`, `14.7.3`) last exited 0.

## Working agreement with the consumer

The consumer project directs the seeding work (Tim
delegated 2026-09-03). Seeding lives **here**; their skill is strictly read-only
and only reads what we create. Two instances at a time, teardown between
batches — sequential recording is fine, so the ceiling never dictates which
boundaries can be measured.

**Findings that cross between sessions need their controls attached, not just
their results.** A 403 with a plausible story is indistinguishable from a real
one at the receiving end.

**Licences expire 2026-09-29.** After that, provisioning fails for every version
at once (K13).

## The recurring failure shape — now four instances of it

Every significant bug found in this project, on both sides, has the same shape:
**a step reports success while producing something unusable**, and it survives
the first run to fail on a differently-timed second one.

1. Readiness probed nginx, not the backend — "ready" while `dsscli` could not connect.
2. `api-keys-list` returned `******` on 13.x — a masked string stored as a credential.
3. The consumer's dependency detector returned `{}` — its test data was written
   to match the code's assumption, so it always passed.
4. A **403** read as "capability absent" when it was really "project does not
   exist" — caught only by probing a control endpoint whose presence was certain.

The defence that works is **structure, not care**: a control row in the results
table, an assertion on a match count, a credential proven by use. Care does not
survive a tired session.

### Three corollaries, each learned the hard way

**1. The verification needs its own control.** Three times in one day the flaw
was in the check rather than the thing checked:

- A `403` read as "capability absent" — it meant "project does not exist".
- A lint gate "verified" with 95 identical characters. It passed, which looked
  like proof. MD013 ignores lines with no spaces, so the probe **could not
  fail** — a pass proved nothing.
- (Consumer's) counting entries where `trigger == "major_boundary"` returned
  zero and appeared to contradict an agent's report. `trigger` is an **object**;
  the comparison could never have matched.

**A disconfirming result is exactly as suspect as a confirming one — and more
dangerous**, because it arrives feeling like diligence. Before believing a probe,
establish that it can produce the other answer.

**2. Having the check is not having the gate.** Markdown lint violations reached
three commits here while the check existed, ran, and enforced nothing — its `&&`
guarded only an `echo`. The consumer's parallel: a schema validator documented
and runnable locally, with no CI step, passing for weeks while gating no push.

**3. Do not industrialise a signal whose inputs are unverified.** The
route-registration screen (ROADMAP phase 8) must not be built until the two
wrong-URL rows are resolved. A screen built on guessed paths would mass-produce
the exact false-negative it exists to catch — the difference between a screen and
a false-negative factory.

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
