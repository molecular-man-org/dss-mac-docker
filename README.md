# dss-mac-docker

Run **any Dataiku DSS version from 11.0.0 to 15.0.0** on macOS with Docker
Desktop — as a provisioning backend for other agents, or by hand:

```text
dss-lab provision 12.3.1 --output json   # {url, api_key, nickname}
/start-dss-container 12.3.0              # or just ask for one
```

Its main consumer is the `dss-headless-upgrade-planning-skill` project, which
needs old DSS versions stood up on demand to test compatibility matrices
against. See [docs/PROVISIONING.md](docs/PROVISIONING.md).

> **Status: v0.1.0.** Provisioning works end to end and is verified on the 12.x
> and 14.x eras. See [CHANGELOG.md](CHANGELOG.md) for what is and is not proven,
> and [docs/HANDOFF.md](docs/HANDOFF.md) to pick up the work.

---

## Why this exists

Dataiku publishes 109 DSS versions in the 11.x-15.x range, but only **14** of
them exist as Docker Hub images. Reproducing a customer's exact patch version —
12.6.7, 13.5.7, 14.7.3 — means building it, and building it naively on an Apple
Silicon Mac means an hour of emulated R compilation per version.

This repo makes any of the 109 reachable in minutes, and makes starting one a
single sentence.

## For a calling agent

This repo is a **provisioning backend**. Shell out to the CLI; there is nothing
to install and no shared state to coordinate.

```bash
/path/to/dss-mac-docker/bin/dss-lab provision 12.6.4 --output json
```

stdout is **only** the JSON below; all logging goes to stderr, so pipe it
straight into a parser. Exit code is `0` on success, non-zero on failure.

```json
{
  "nickname": "dss-12.6.4",
  "url": "http://localhost:11640",
  "api_key": "...",
  "version": "12.6.4",
  "container": "dss-12.6.4",
  "licence": "dev-timhonker-2024.json",
  "status": "ready"
}
```

The instance is also registered in `~/.dataiku/config.json`, so a
`dataiku-headless` client can connect with **just the nickname** —
`switch_instance("dss-12.6.4")` — and no credential has to travel between
agents.

**Call it as often as you like.** `provision` is idempotent: an existing
instance is started rather than rebuilt, and its existing API key is reused
rather than a second one minted.

Budget for it: a version already built starts in **under a minute**; one that
must be built takes **several minutes** (a ~2 GB kit download plus install under
emulation). `provision` blocks until DSS actually answers, so a slow return is
progress, not a hang.

Version specs are flexible — `12.6.4`, `12.6`, `13`, `latest` all resolve.
`dss-lab catalog` lists all 109.

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
| [PROVISIONING.md](docs/PROVISIONING.md) | **The contract with calling agents** |
| [ROADMAP.md](docs/ROADMAP.md) | Six phases with exit criteria |

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
