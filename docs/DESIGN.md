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

## D3. Two-stage build, with the era base pulled from Hub

Build-from-kit is the primary path (RESEARCH §3), so it has to be fast. Two
compounding fixes:

**Stage 1 — era base.** Do not build one from scratch. `dataiku/dss:15.0.0`
*already is* the al9 era with every OS dependency installed and every R package
compiled. Use the nearest Hub tag in the same era as the base:

| Era | Era base | Covers |
| --- | --- | --- |
| 11.x - 12.x | `dataiku/dss:12.6.4` | 47 versions |
| 13.x | `dataiku/dss:13.4.4` | 30 versions |
| 14.x - 15.x | `dataiku/dss:15.0.0` | 32 versions |

**Stage 2 — per-version layer.** Declare the version ARG *below* everything
expensive, fixing the upstream caching flaw (RESEARCH §8):

```dockerfile
FROM dataiku/dss:15.0.0
ARG dssVersion                 # declared late: base layers stay cached
RUN <download kit> && <extract> && <installdir-postinstall.sh> && <npm puppeteer>
```

Each of the ~95 non-Hub versions becomes a kit download plus install — minutes,
not an hour of emulated R compilation.

**Cost:** the era base carries a dead ~3 GB kit for its own DSS version in a
lower layer, so removing it in stage 2 reclaims nothing. That is ~3 GB per era,
shared by every version in the era. Good trade against a 60-minute emulated
build. `--era-base scratch` builds clean from `almalinux:8`/`:9` using the
transcribed upstream recipe for when it matters.

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

## D7. Memory profile written at first boot

The 6.25 GB VM is the binding constraint (RESEARCH §1) and DSS 14/15 assumes far
more. On first boot `up` writes a reduced backend heap into
`$DSS_DATADIR/bin/env-site.sh` before starting DSS.

Sizing is deliberately left as a phase-2 measurement rather than a guess — the
right heap has to come from watching a real instance, not from arithmetic.

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
matched by **glob**, never by exact filename: the `timhonker` portion belongs to
one user's licence set and must not be hard-coded.

The licence directory is untracked and configurable via `DSS_LAB_LICENSE_DIR`.
Licence files must never be committed.
