# Public release plan

What stands between the repository as it is and a public release that a stranger
can clone, follow the README, and trust. Written 2026-09-25 from the state at
commit `61bc90e`. It is a plan, not a record: tick items as they land, and move
anything that turns out not to matter to the bottom rather than deleting it.

For what has already been measured, see the
[compatibility matrix](compatibility-matrix.md). For the feature phases, see the
[roadmap](ROADMAP.md).

## Where things stand

- **Working and verified on real containers:** provisioning, snapshots, restore,
  guarded upgrades (12.6.4 → 13.4.4 → 14.7.0 → 15.0.0), project import, licence
  handling by tier, and boots from 11.0.0 to 15.0.0.
- **Covered by automated checks:** 279 unit assertions that need no Docker, plus
  shellcheck and markdownlint, all in CI on macOS and Linux.
- **Not yet proven:** anything past a bare project. Upgrades and imports have only
  been tried with empty projects, and only 14 of the 109 versions have been run.
- **Not yet done for a stranger:** nobody has followed the README on a clean
  machine.

## 1. Before publishing

These gate everything else. They are decisions and checks, not engineering.

- [ ] **Ownership and permission.** Confirm the repository may be published, and
      that the copyright holder named in [LICENSE](../LICENSE) is correct. The
      licence file is currently a verbatim copy of another project's, including
      its copyright line.
- [ ] **Fresh-machine test.** Clone into a clean directory or a second user
      account, put licences in `~/.dataiku/licenses`, and follow only the README.
      Record every place it needed knowledge the README does not give, and fix the
      README, not the tester.
- [ ] **Working notes out of the way.** [HANDOFF.md](HANDOFF.md) and
      [ERA_CONTENT_PLAN.md](ERA_CONTENT_PLAN.md) are written for the people who
      built this, and refer to a "consumer project" and a "peer session" a reader
      cannot see. Rewrite them for outsiders or remove them, and check the other
      docs for the same voice.
- [ ] **Publish from clean history.** Older commits contain files that no longer
      exist, some embedding local paths. Recreate the repository, or purge the old
      history with the host's support, rather than relying on a force-push: the
      host may keep old commits reachable by hash for a while.
- [ ] **Commit author identity.** Decide which name and address the public commits
      carry, and set it before the history that will be published is created.
- [ ] **Visibility.** Change it only after the items above.

## 2. What would most improve what the tool proves

- [ ] **Seed with realistic content** ([roadmap](ROADMAP.md) phase 7). An empty
      instance exercises almost nothing that an upgrade check cares about. Import
      real project exports with `dss-lab bundle`, upgrade them across versions,
      and record what breaks: flows, recipes, code environments, plugins. This is
      the largest gap between what the matrix claims and what it shows.
- [ ] **Automate the matrix.** A `verify` command that builds or pulls a
      version, provisions it, probes the licence tiers, measures idle memory, and
      cleans up after itself, printing one matrix row. It exists today only as
      throwaway scripts, and only 14 of the 109 versions have been run. It would
      also flag a first boot far slower than its neighbours, which is how a real
      11-minute defect was found ([known issue K14](KNOWN_ISSUES.md)). A sweep of
      all 109 versions is roughly a working day of machine time and needs
      per-version cleanup to keep the Docker VM's disk from filling.
- [ ] **Finish the licence read-back gate.** `dsscli set-license` exits 0 for a
      licence the node cannot parse, so today the only protection is skipping the
      2025-tier licences below 12.6.0. Confirm success by reading the licensing
      status back. That needs an API key, which `provision` currently creates
      after the licence, so the order has to change with care. The same change
      fixes a leftover licence copy in the container's `/tmp`.

## 3. Cheap robustness

- [ ] **Guard the Docker VM's disk.** During the boundary builds the build cache
      reached 55 GB on a 160 GB VM and had to be pruned by hand. `doctor` and
      `build` should check free space first and point at `gc`.
- [ ] **Extend the Claude skills.** They cover start, stop and list; add
      `upgrade`, `snapshot` and `bundle`.
- [ ] **Tag a release.** Date the changelog, tag `v0.2.0`, and publish release
      notes.
- [ ] **Keep CI honest.** The Docker-dependent paths cannot run in CI (DSS is
      x86-only and needs emulation), so say so in the README and keep the
      compatibility matrix as the evidence for them.

## 4. Optional

- [ ] Intel Mac and Linux support. There is no emulation cost there, but the code
      assumes Docker Desktop on macOS in a few places.
- [ ] Tidy the roadmap: phase 8 is listed before phase 7.

## Suggested order

1. The ownership question, the fresh-machine test, and the working notes. They
   gate publishing and are cheap.
2. Realistic seeding and the licence read-back gate. They most improve what the
   repository can honestly claim.
3. The verify command and the disk guard, which turn one-off measurements into
   something repeatable.
4. Publish, then tag.

## Done means

A stranger can clone the repository, follow the README with their own licences,
provision any of the versions the matrix lists, and get the results the matrix
reports. Nothing in the tree refers to people or systems they cannot see, and the
published history contains only what is meant to be public.
