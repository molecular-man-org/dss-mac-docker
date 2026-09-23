# Design

Rationale for the architecture. Facts it rests on are in
[RESEARCH.md](RESEARCH.md); open risks are in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

---

## D1. Version is the identity

**One container per DSS version. No second instance of the same version, ever.**

Every name and the port derive from the version by pure function, so there is no
allocation step, no registry to keep in sync, and no collisions.

| Thing | Pattern | Example (`12.3.0`) |
| --- | --- | --- |
| Container | `dss-<version>` | `dss-12.3.0` |
| Volume | `dss-<version>-data` | `dss-12.3.0-data` |
| Host port | `10000 + (major-11)*1000 + minor*100 + patch*10` | `11300` |
| Image (pulled) | `dataiku/dss:<version>` | `dataiku/dss:12.6.4` |
| Image (built) | `dss-mac-docker/dss:<version>` | `dss-mac-docker/dss:12.3.0` |

Verified collision-free across all 109 in-range versions (RESEARCH §9). Docker
permits `.` in names, so `dss-12.3.0` is valid.

The port is legible on sight — `12.3.0` → `11300`, `14.7.3` → `13730` — which
matters because the user reads it off a URL constantly.

**Port collisions still get a guard.** The formula only stays injective while
minor and patch are ≤ 9. If a computed port is occupied by something that is not
this version's container, fall back to the next free port and record it on the
container label; the label, never the formula, is what `ls` and `url` read back.

## D2. Docker labels are the only state

No state file. Both container and volume carry:

```text
dss-mac-docker.managed=true
dss-mac-docker.version=<version>
dss-mac-docker.port=<actual port>
dss-mac-docker.source=hub|build
dss-mac-docker.era=dss11-12|dss13|dss14-15
```

`ls` is `docker ps -a --filter label=dss-mac-docker.managed=true`. Nothing can
drift, a manually removed container leaves no stale record, and the tool holds no
lock on anything.

The **volume's** `version` label additionally records which DSS version last
wrote the datadir — that is what makes the irreversible-upgrade guard in D5
possible.

## D3. Two-stage build, on a same-major Hub base

Build-from-kit is the primary path (RESEARCH §3), so it has to be fast. Two
compounding fixes:

**Stage 1 — reuse a published image as the base.** Do not build one from
scratch. `dataiku/dss:14.7.0` *already is* an al9 DSS with every OS dependency
installed and every R package compiled.

The base is chosen **same-major**, not same-era. An era spans two majors, and a
14.x kit on a 15.0.0 base would inherit 15's Python. `major_base_image()`:

| Major | Base | Major | Base |
| --- | --- | --- | --- |
| 11.x | `dataiku/dss:11.2.0` | 14.x | `dataiku/dss:14.7.0` |
| 12.x | `dataiku/dss:12.6.4` | 15.x | `dataiku/dss:15.0.0` |
| 13.x | `dataiku/dss:13.4.4` | | |

`build_base_for()` then prefers **any same-major Hub image already present
locally** over pulling the canonical one, because fetching another 3-4 GB base
to build one version defeats the purpose. `--base IMAGE` overrides. The base
actually used is recorded on the image as `dss-mac-docker.base`, so a build is
always traceable to what it came from.

The era is still the right granularity for toolchain metadata — the puppeteer
pin (`era_puppeteer`) and the dnf repo flag — just not for the base image.

**Stage 2 — per-version layer.** Declare the version ARG *below* everything
expensive, fixing the upstream caching flaw (RESEARCH §8):

```dockerfile
ARG BASE_IMAGE=dataiku/dss:12.6.4
FROM ${BASE_IMAGE}
ARG DSS_VERSION_ARG          # declared late: base layers stay cached
ARG PUPPETEER_VERSION
RUN <download kit> && <extract> && <installdir-postinstall.sh> && <npm puppeteer>
ENV DSS_VERSION=${DSS_VERSION_ARG}
```

Setting `ENV DSS_VERSION` is what redirects the base's inherited `run.sh` onto
the newly installed kit. **One parameterised Dockerfile covers every era**, since
the era only selects `BASE_IMAGE` and `PUPPETEER_VERSION`; per-era Dockerfiles
would only be needed for a from-scratch build, which is not implemented.

**Cost:** the base carries a dead ~3 GB kit for its own DSS version in a lower
layer, so deleting it in stage 2 reclaims nothing. Measured: a built 12.6.7 image
is 17.3 GB against a 10.8 GB base. That is the documented trade for skipping an
hour of emulated R compilation, and the dead weight is shared by every version
built on that base.

## D4. `up` is idempotent and never prompts

Explicit requirement. `/start-dss-container 12.3.0` resolves the version, then
branches on container state:

| State | Action |
| --- | --- |
| Running | Report URL. Exit. |
| Stopped | `docker start` → wait ready → report URL |
| Absent | Ensure image (pull or build) → `docker run` → wait ready → report URL |

No confirmation on any branch, including first-time create.

**Hard stops** (failures, not choices): Docker daemon not running — offer
`open -a Docker`; unresolvable version; insufficient VM disk for the image.

**Announce but proceed** (do not gate): a first-time build costs ~10 min and
several GB; starting a third instance on a 6.25 GB VM will thrash — name which
containers to stop, then continue.

**Version-spec resolution** is the one genuinely fuzzy step, and belongs to the
skill layer: `v12.3.0`, `12.3.0`, `12.3`, `13`, `latest` all resolve to a
concrete version via `dss-lab resolve`, which reads
`data/versions-11plus.txt`. Bare `12.3` means the newest 12.3.x.

## D5. Named volumes only, and guarded upgrades

**Never bind-mount the datadir from macOS.** DSS uses H2 with file locks and
runs as uid `dataiku`; over gRPC-FUSE that produces both lock failures and
ownership mismatches. Datadirs are named Docker volumes; backup goes through
`snapshot`/`export`, not a host path.

`run.sh` silently migrates a datadir when the version differs, and there is no
downgrade (RESEARCH §7). Therefore:

- `up` compares the volume's `version` label to the requested version. If they
  differ it **refuses** unless `--migrate` is passed. This is the one place the
  no-prompt rule yields, because the operation is irreversible.
- `upgrade <from> <to>` snapshots the volume first, then lets `run.sh` migrate.

## D6. Skill layer is thin on purpose

Three skills over one CLI. The slash command is the skill name, so lifecycle
verbs are separate skills:

| Skill | Invocation |
| --- | --- |
| `start-dss-container` | `/start-dss-container 12.3.0`, "create a new instance of DSS v12.3.0" |
| `stop-dss-container` | `/stop-dss-container 12.3.0` |
| `list-dss-containers` | `/list-dss-containers` |

Each `SKILL.md` does three things: resolve the version spec, shell out to
`bin/dss-lab`, report the URL. **All real logic lives in the CLI**, so it is
testable without an LLM in the loop and the skill cannot drift from it.

`make install` creates `~/.claude/skills/` (it does not exist yet) and symlinks
the three skill directories out of this repo, so edits take effect with no
reinstall. If Claude Code turns out not to follow symlinks there, fall back to
copying — **this is unverified**, see KNOWN_ISSUES.

## D7. Memory profile — measured, and deliberately not implemented

The plan was to write a reduced backend heap into `$DSS_DATADIR/bin/env-site.sh`
at first boot, with sizing left as a measurement rather than a guess.

**The measurement came back and the answer is: do nothing.** A DSS 12.x instance
idles at ~2 GiB, and two ran side by side on a 10 GB VM without pressure
([finding](findings/built-image-verified.md)). Writing a smaller heap would slow
DSS down to solve a problem that does not exist.

`up` still sets a container memory ceiling derived from the VM size. Heap tuning
stays unimplemented until 14.x/15.x — larger images, unmeasured — or a real
workload demonstrates it is needed.

This is the design working as intended: the measurement was the deliverable, and
it retired the feature.

## D8. Provisioning is the primary interface

The main consumer is another Claude project, not a human
([PROVISIONING.md](PROVISIONING.md)). That inverts several defaults:

- **Output is structured.** `provision --output json` emits
  `{nickname, url, api_key, ...}`. Human-readable output is the secondary mode.
- **Nothing may prompt.** Already true of `up` by requirement (D4); it now also
  binds licence application and key minting.
- **Idempotency extends to credentials.** Re-provisioning an existing instance
  returns its existing details rather than minting a second API key.
- **The handoff is by nickname, not by credential.** Registering into
  `~/.dataiku/config.json` means the calling agent needs only the nickname, and
  no API key has to travel between agents.

`/start-dss-container` is a thin human veneer over `provision`.

## D9. Licence selection walks an ordered preference list

Licence rejection is an expected outcome, not an error, because the licences
differ by feature tier and older DSS may not parse newer offer strings (K10).

So `provision` tries licences in a documented order — `dev-*-2024.json` first —
and continues down the list until DSS accepts one, reporting which. Files are
matched by **glob**, never by exact filename: the user portion of the filename
belongs to one licence set and must not be hard-coded.

The licence directory is untracked and configurable via `DSS_LAB_LICENSE_DIR`.
Licence files must never be committed.
