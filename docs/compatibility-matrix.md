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
| 11.2.0 | accepted | **rejected (400)** | accepted |
| 12.4.2 | accepted | **rejected (400)** | accepted |
| 12.6.4 | accepted | accepted | accepted |
| 13.4.4 | accepted | accepted | accepted |
| 14.7.0 | accepted | accepted | accepted |
| 15.0.0 | accepted | accepted | accepted |

The 2025 tiers first work at some version between 12.4.2 and 12.6.4, consistent
with the documented 12.6.0 floor. 12.6.0 itself has not been booted, so the exact
boundary is taken from that floor rather than measured. `provision` skips the
2025 tier below 12.6.0.

Under the 2025 tiers `FULL_DESIGNER` is offered on every version that accepts
them; under 2024, `DESIGNER`.

## Boot and provisioning

`provision` succeeds (container up, licensed, admin key minted and working) on:

| DSS | Source | Notes |
| --- | --- | --- |
| 11.2.0 | Hub image | ready in ~20s on a warm start |
| 12.4.2 | built from kit | ~35s |
| 12.6.4 | Hub image | |
| 12.6.7 | built from kit | |
| 13.4.4 | Hub image | reached by upgrade from 12.6.4 |
| 13.5.7 | built from kit | |
| 14.7.0 | Hub image | reached by upgrade from 13.4.4 |
| 14.7.3 | built from kit | |
| 15.0.0 | Hub image | reached by upgrade from 14.7.0 |

Not run: any version other than those above, and 11.0.0 to 11.1.x in particular.

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

- Memory profile per era, and running several versions at once.
- Realistic content: upgrades of a project with flows, recipes and code envs
  (see [SEEDING.md](SEEDING.md)).
- Versions other than those listed above.
