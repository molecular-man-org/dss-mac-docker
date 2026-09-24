# Compatibility matrix

What has been booted and measured on real containers, on an Apple Silicon Mac
under Rosetta emulation. Everything here was observed, not inferred; anything not
listed has **not** been run. The catalogue has 109 versions; this covers the
boundaries and one or more representatives of every release era.

## Licence tiers by DSS version

Applied with `dss-lab license <version> <file>` and verified by reading
`GET /admin/licensing/status` back. `dsscli set-license` exits 0 for a licence the
node cannot parse, so the exit code proves nothing; only the read-back does.
See [LICENCES.md](LICENCES.md) for what each tier is.

| DSS | 2024 | 2025 (all three) | 2018 |
| --- | --- | --- | --- |
| 11.0.0 | accepted | **rejected (400)** | accepted |
| 11.2.0 | accepted | **rejected (400)** | accepted |
| 11.4.5 | accepted | **rejected (400)** | accepted |
| 12.4.2 | accepted | **rejected (400)** | accepted |
| 12.5.2 | accepted | **rejected (400)** | accepted |
| 12.6.0 | accepted | accepted | accepted |
| 12.6.4 | accepted | accepted | accepted |
| 13.4.4 | accepted | accepted | accepted |
| 14.7.0 | accepted | accepted | accepted |
| 15.0.0 | accepted | accepted | accepted |

The 2025 tiers first work at **12.6.0**: 12.5.2 (the newest 12.5.x) rejects them
and 12.6.0 accepts them, so the boundary is measured, and it matches the
documented floor. `provision` skips the 2025 tier below 12.6.0.

Under the 2025 tiers `FULL_DESIGNER` is offered on every version that accepts
them; under 2024, `DESIGNER`.

## Boot and provisioning

`provision` succeeds (container up, licensed, admin key minted and working) on:

| DSS | Source | Notes |
| --- | --- | --- |
| 11.0.0 | built from kit | the bottom of the range; 176s from nothing to licensed, build included |
| 11.2.0 | Hub image | ready in ~20s on a warm start |
| 11.4.5 | built from kit | 180s from nothing, build included |
| 12.4.2 | built from kit | ~35s |
| 12.5.2 | built from kit | first boot was **650s** until the Puppeteer fix below; 35s since |
| 12.6.0 | built from kit | 207s from nothing, build included |
| 12.6.4 | Hub image | |
| 12.6.7 | built from kit | |
| 13.4.4 | Hub image | reached by upgrade from 12.6.4 |
| 13.5.7 | built from kit | |
| 14.7.0 | Hub image | reached by upgrade from 13.4.4 |
| 14.7.3 | built from kit | |
| 14.4.1 | Hub image | cold pull and first boot in 143s; a second `up` is a 1s no-op |
| 15.0.0 | Hub image | reached by upgrade from 14.7.0 |

Times are wall-clock under Rosetta on one machine and vary with load. The
catalogue has 109 versions; the ones above are what has been run, and any other
version is expected to behave like its neighbour but is not measured.

### A first-boot slowdown, found and fixed

12.5.2 took 650s to first answer, twice, while every other built version took
under a minute. The container log showed why: on first boot `run.sh` runs the
kit's `install-graphics-export`, which picks a Puppeteer version from the Node.js
version (`added 71 packages ... in 10m`). The image had pre-installed a different,
era-wide pin, so npm re-downloaded Puppeteer and Chromium under emulation. The
build now asks the kit which version it will want (`docker/kit-puppeteer.sh`) and
pre-installs that. 12.5.2 then booted in 35s, and a control rebuild of 12.6.0 was
unchanged (207s against 234s). See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) K14.

## Memory

Idle memory three minutes after the backend answered, one node at a time on the
10 GB Docker VM. DSS already caps its JVM heaps at 2 GiB each (DESIGN D7).

| DSS | Idle memory |
| --- | --- |
| 12.6.4 | 1.9 GiB |
| 13.4.4 | 1.9 GiB |
| 14.7.0 | 2.5 GiB |
| 15.0.0 | 2.4 GiB |

An idle node only: jobs, recipes and ML will use more, and that is not measured.

## Upgrade paths

`dss-lab upgrade <from> <to>` clones the datadir and lets DSS migrate the clone
(DESIGN D5). A marker project created on 12.6.4 was present, with its licence,
after every hop:

| Hop | Result | Backend ready after |
| --- | --- | --- |
| 12.6.4 → 13.4.4 | migrated, marker project present | 40s |
| 13.4.4 → 14.7.0 | migrated, marker project present | 70s |
| 14.7.0 → 15.0.0 | migrated, marker project present | 75s |

Each source node was left stopped and untouched. The marker is a bare project,
not a realistic one: this shows the datadir migrates and survives, not that any
particular flow, recipe or code environment does.

## Importing a project export

`dss-lab bundle` imports a project export archive. A bare project (no datasets or
recipes) exported from 15.0.0 imported into 12.6.4, with a warning about plugins
the archive expects, and one exported from 12.6.4 imported into 14.7.0. Realistic
projects are not yet measured.

## Snapshots

On 11.2.0: a marker project was created, `snapshot` taken (the node was stopped
and restarted around the copy, 24s in all), the project deleted, then `restore
--force` brought it back. `restore` without `--force` refuses.

## Admin profile

A fresh DSS stores admin as `DATA_SCIENTIST`, which the 2024 and 2025 tiers do
not offer, so DSS silently demotes admin to the tier's fallback profile
(`EXPLORER` under 2024). `provision` now sets admin to the tier's maximum
productive profile and reads it back. Observed on 11.2.0, 12.6.4, 13.4.4 and
15.0.0: `DATA_SCIENTIST` → `DESIGNER` under 2024, and → `FULL_DESIGNER` under a
2025 licence on 12.6.4. A licensed profile already on admin is left alone.

## Not yet covered

- Running several versions at once, and memory under load.
- Realistic content: upgrades of a project with flows, recipes and code envs
  (see [SEEDING.md](SEEDING.md)).
- Versions other than those listed above.
