# dss-mac-docker

Run **any Dataiku DSS version from 11.0.0 to 15.0.0** on macOS with Docker
Desktop, driven by a Claude Code skill:

```text
/start-dss-container 12.3.0
"create a new instance of DSS v12.3.0"
```

> **Status: planned, not built.** Research and design are complete and verified;
> no implementation code exists yet. Start at
> [docs/HANDOFF.md](docs/HANDOFF.md).

---

## Why this exists

Dataiku publishes 109 DSS versions in the 11.x-15.x range, but only **14** of
them exist as Docker Hub images. Reproducing a customer's exact patch version —
12.6.7, 13.5.7, 14.7.3 — means building it, and building it naively on an Apple
Silicon Mac means an hour of emulated R compilation per version.

This repo makes any of the 109 reachable in minutes, and makes starting one a
single sentence.

## How it works

One container per DSS version, with the version as the identity. Every name and
the port derive from it by pure function, so there is nothing to allocate and
nothing to collide:

| Thing | Pattern | `12.3.0` |
| --- | --- | --- |
| Container | `dss-<version>` | `dss-12.3.0` |
| Volume | `dss-<version>-data` | `dss-12.3.0-data` |
| URL | `10000 + (major-11)*1000 + minor*100 + patch*10` | <http://localhost:11300> |

Starting a version that already exists just starts it — no prompt, no duplicate.

Images come from Docker Hub when published, and are otherwise built from the
official installer kit on top of the nearest Hub image in the same release era,
which skips the expensive R build entirely.

## Requirements

- Apple Silicon Mac with Docker Desktop (`/Applications/Docker.app`)
- **Rosetta emulation enabled** — DSS ships x86-64 only
- Docker VM with ~10 GB RAM recommended; 6.25 GB is the current default and is
  the binding constraint on running several versions at once

## Documentation

| Doc | What it covers |
| --- | --- |
| [HANDOFF.md](docs/HANDOFF.md) | **Start here.** Current state, decisions, next actions |
| [RESEARCH.md](docs/RESEARCH.md) | Verified findings, with how each was checked |
| [DESIGN.md](docs/DESIGN.md) | Architecture and the reasoning behind it |
| [KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) | Risks, traps, and open unknowns |
| [ROADMAP.md](docs/ROADMAP.md) | Five phases with exit criteria |

## Layout

```text
bin/dss-lab          # the CLI; all real logic lives here
bin/lib/             # common.sh, catalog, image, instance
docker/              # one Dockerfile per release era
skills/              # thin Claude Code skills over the CLI
data/                # version lists captured during research
docs/                # see table above
tests/run_tests.sh   # unit tests, no Docker required
```
