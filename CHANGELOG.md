# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added

- **`snapshot`, `restore`, `upgrade`** — datadir snapshots and guarded upgrades.
  `upgrade <from> <to>` migrates a clone and leaves `from` untouched as the
  rollback. Verified live: a marker project survived 12.6.4 → 13.4.4 → 14.7.0.
- `docs/LICENCES.md` and a root `CLAUDE.md` recording which licence suits which
  DSS version.
- `provision` skips the 2025-tier licences on DSS older than 12.6.0.
- `provision` repairs a demoted admin user and reports `admin_profile` in its
  JSON: it sets the licence tier's maximum productive profile and reads it back.
- `docs/compatibility-matrix.md` — measured licence, boot and upgrade results.
- GitHub Actions CI: the test suite (macOS and Linux), shellcheck, markdownlint.

- **`bundle <spec> <file.zip>`** — imports a DSS project export archive into a
  running instance (`--project-key`, `--remap-connection`). Verified live in both
  directions across versions. The archive is validated first, and the copy in the
  container is removed even when the import fails.

### Fixed

- **First boot of some built versions took 11 minutes** (12.5.2 measured). The
  image pre-installed an era-wide Puppeteer pin, but the kit picks its own from
  the Node.js version, so first boot re-downloaded Puppeteer and Chromium. The
  build now asks the kit (`docker/kit-puppeteer.sh`); 12.5.2 boots in 35s.

### Changed

- The README now lists the commands, the full docs set and the real layout.
- Phase 2, 3 and 6 of the roadmap are closed. The memory profile is measured and
  deliberately not implemented (idle 1.9-2.5 GiB from 12.x to 15.x); from-scratch
  builds (`--era-base scratch`) are decided against.
- Prepared for public release: Apache-2.0 `LICENSE` added; the licence folder now
  defaults to `~/.dataiku/licenses` (set `DSS_LAB_LICENSE_DIR` to use
  another); personal identifiers and internal hostnames removed from docs and
  test fixtures.

### Removed

- The per-licence tier measurements and the scripts that produced them.

## [0.1.0] — 2026-09-03

First tagged release. Provisions any Dataiku DSS version from 11.0.0 to 15.0.0
on macOS with Docker Desktop, and hands the connection details to a calling
agent.

### Added

- **`provision <spec> --output json`** — the primary interface. Creates or
  starts a container, applies a licence, mints an admin API key, registers the
  instance in `~/.dataiku/config.json`, and emits
  `{nickname, url, api_key, version, container, licence, status}` on stdout.
  Unattended; never prompts.
- **Lifecycle** — `up`, `ls`, `stop`, `url`, `logs`, `shell`, `rm`, `gc`.
  `up` is idempotent: running is a no-op, stopped starts, absent creates.
- **`build <spec>`** — builds any of the ~95 versions Docker Hub does not
  publish, on top of the nearest same-major Hub image, which skips the
  hour-long emulated R compile.
- **`doctor`**, **`catalog`**, **`resolve`**, **`info`**, **`versions`**.
- **Three Claude skills** — `start-dss-container`, `stop-dss-container`,
  `list-dss-containers`, installed by `make install`.
- **167 assertions** in `tests/run_tests.sh`, requiring no Docker daemon.

### Verified

| Era | Version | Path | Port | Result |
| --- | --- | --- | --- | --- |
| 11.x | 11.2.0 | pull | 10200 | provisioned, licensed, admin key works |
| 12.x | 12.6.4 | pull | 11640 | provisioned, licensed, admin key works |
| 12.x | 12.6.7 | build | 11670 | provisioned, licensed, admin key works |
| 13.x | 13.5.7 | build | 12570 | provisioned, licensed, admin key works |
| 14.x | 14.7.3 | build | 13730 | provisioned, licensed, admin key works |

All four release eras (`dss11-12`, `dss13`, `dss14-15`) exercised on both the
pull and build paths. A `dev-*-2024.json` licence was accepted by every one.
Stored API keys survive a container stop/start.

`dataiku-headless` connected to a provisioned instance **by nickname alone**,
with no credential passed between agents.

### Safety

- `~/.dataiku/config.json` holds live production credentials. Writes back it up,
  refuse to overwrite a config that will not parse, refuse to drop any existing
  instance, write atomically at mode `0600`, and never touch `default_instance`.
  Both refusals are mutation-tested.
- Starting a version against a datadir written by a different version is refused
  without `--migrate`, because DSS migrates in place with no downgrade.
- Licence files are gitignored by patterns matching their real names.

### Fixed during release preparation

- `docker pull` writes progress to stdout, which corrupted
  `provision --output json` whenever a base image was not already cached.
- DSS 13.x **masks** API key secrets in `api-keys-list` (`******`) where 12.x
  discloses them, so the reuse path stored a six-asterisk placeholder as a
  credential. Keys are now validated by using them
  ([finding](docs/findings/api-keys-are-masked-on-some-versions.md)).
- `dsscli` prefixes stdout with a log line on first invocation, breaking JSON
  parsing.
- Readiness probed nginx rather than the DSS backend, so `dsscli` calls could run
  before the backend was listening
  ([finding](docs/findings/readiness-must-probe-the-backend.md)).

### Known limitations

- **15.x is unexercised** — it is the only line with no verified version.
- API keys differ by line — 32 chars on 12.x, 39 on 13.x/14.x. Assume nothing
  about length.
- A key masked by DSS cannot be deleted programmatically, because
  `api-key-delete` takes the secret. `dss-13.5.7` carries one orphaned key from
  before the fix; it does not accumulate further.
- The licence fallback order has never run against a real rejection —
  `dev-*-2024.json` was accepted first try everywhere it was tried.
- **All available licences expire 2026-09-29.** After that, provisioning fails
  for every version at once.
- Newly provisioned instances are **empty**, which makes them weak upgrade-test
  targets. Seed content is phase 7, research only.
- `snapshot` / `restore` / `upgrade` are not implemented.
