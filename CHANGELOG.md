# Changelog

All notable changes to this project are documented here.

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

| Era | Version | Path | Result |
| --- | --- | --- | --- |
| 12.x | 12.6.4 | pull | provisioned, licensed, admin key works |
| 12.x | 12.6.7 | build | provisioned, licensed, admin key works |
| 14.x | 14.7.3 | build | provisioned, licensed, admin key works |

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

### Known limitations

- **13.x is unverified** at time of tagging.
- **11.x and 15.x are entirely unexercised.**
- The licence fallback order has never run against a real rejection —
  `dev-*-2024.json` was accepted first try everywhere it was tried.
- **All available licences expire 2026-09-29.** After that, provisioning fails
  for every version at once.
- Newly provisioned instances are **empty**, which makes them weak upgrade-test
  targets. Seed content is phase 7, research only.
- `snapshot` / `restore` / `upgrade` are not implemented.
