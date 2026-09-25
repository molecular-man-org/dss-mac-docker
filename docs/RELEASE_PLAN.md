# Public release plan

What stands between the repository as it is and a public release that a stranger
can clone, follow the README, and trust. Revised 2026-09-25 against the public
[`dataiku-headless`](https://github.com/dataiku/dataiku-headless) repository,
which is used as the reference for scope and quality. It is a plan, not a record:
tick items as they land, and move anything that stops mattering to the bottom
rather than deleting it.

For what has been measured, see the
[compatibility matrix](compatibility-matrix.md). For the feature phases, see the
[roadmap](ROADMAP.md).

## Decisions

Taken 2026-09-25, after comparing this repository with the reference.

| Topic | Decision | Consequence |
| --- | --- | --- |
| Ownership | A personal or community project now, designed so it can move into a company organisation later | Neutral wording throughout; no company branding; the "unofficial" disclaimer stays |
| Copyright line | `dss-mac-docker contributors` | `LICENSE` changes from its current verbatim copy; a later transfer is one line |
| Per-file headers | An `SPDX-License-Identifier: Apache-2.0` line in every source file, enforced in CI | Same enforcement as the reference, without a holder name in every file |
| Working documents | Keep the evidence (design, known issues, research, findings); drop the handoff and planning notes | `HANDOFF.md` and `ERA_CONTENT_PLAN.md` leave the public tree |
| Releases | Full automation: enforced Conventional Commits; each merge to `main` bumps the version, tags, updates the changelog and publishes a release | Needs a version source, a bump workflow and a baseline tag; see the risk below |
| Scaffolding | Match the reference and fill its gaps | Adds a security policy, code of conduct, dependency updates and a PR template, none of which the reference has |
| Packaging | Ship as an agent plugin **before** the first release | The skills must find the CLI without the install-time path substitution `make install` does |
| Branch rules | Protect `main` (pull request and passing CI required, squash merges only), with an administrator bypass | Direct pushes to `main` stop once the rules are on |

## Where things stand

- **Working and verified on real containers:** provisioning, snapshots, restore,
  guarded upgrades (12.6.4 → 13.4.4 → 14.7.0 → 15.0.0), project import, licence
  handling by tier, and boots from 11.0.0 to 15.0.0.
- **Automated checks:** 279 unit assertions that need no Docker, plus shellcheck
  and markdownlint, all in CI on macOS and Linux.
- **Not yet proven:** anything past a bare project, and 95 of the 109 versions.
  Nobody has followed the README on a clean machine.

### Against the reference

| Area | Reference | Here today |
| --- | --- | --- |
| Contributing | `CONTRIBUTING.md`, four issue forms with blank issues off, an RFC path, a PR-title check | None |
| Contributor guide | A standards document and an `AGENTS.md` listing the sources of truth; `CLAUDE.md` just includes it | A standalone `CLAUDE.md` |
| Releases | Automated version, tag, changelog and release | Hand-written changelog, no tags |
| CI | Pre-commit hooks including private-key detection, a licence-header check, a test matrix, a build smoke test; actions pinned by commit SHA | Tests, shellcheck, markdownlint; actions pinned by tag; secret scanning only locally |
| Working notes | Kept out of the repository | Committed |
| Install | Agent plugin manifests and a marketplace entry | Clone, then `make install` |
| Not in the reference either | Security policy, code of conduct, dependency updates, PR template | Same |

## Work, in order

### A. Identity and hygiene

- [ ] **Confirm there is no objection to publishing personally.** The work was
      done with a company machine and company licences. Confirm with whoever
      needs to know, and record the answer here.
- [ ] **Change the copyright line** in [LICENSE](../LICENSE) to
      `dss-mac-docker contributors`, and keep the disclaimer in the README.
- [ ] **Add SPDX headers** to every shell, Python and YAML source file, and a CI
      job that fails when one is missing (the reference does this with a small
      standard-library script).
- [ ] **Remove the handoff and planning notes** (`HANDOFF.md`,
      `ERA_CONTENT_PLAN.md`), and rewrite what remains, including `DESIGN.md`,
      `KNOWN_ISSUES.md`, `RESEARCH.md`, `SEEDING.md` and the findings, for a
      reader who cannot see the people and systems they mention. Update every
      link that pointed at the removed files.
- [ ] **Fresh-machine test.** Clone into a clean directory or a second user
      account, put licences in `~/.dataiku/licenses`, and follow only the README.
      Record each place it needed knowledge the README does not give, and fix the
      README, not the tester.

### B. Contributor and community scaffolding

- [ ] `CONTRIBUTING.md`: search first, use the forms, propose large changes before
      building them (the reference asks for an RFC above about 500 lines), and
      never include credentials, licences, customer data or instance URLs.
- [ ] **Issue forms** for a bug, a feature, a question and an RFC, with blank
      issues disabled.
- [ ] **Pull request template** with the checklist below.
- [ ] **Contributor guide.** Make `AGENTS.md` the canonical guide, with the
      architecture, the sources of truth and the verification commands, and reduce
      `CLAUDE.md` to an include plus the licence rules. Add the coding standards
      the shell code already follows: `bash` 3.2, `set -e` pitfalls, no editing
      `bin/dss-lab` while it runs, the docs-consistency test.
- [ ] **`SECURITY.md`**, pointing at GitHub private vulnerability reporting, and
      **`CODE_OF_CONDUCT.md`** (Contributor Covenant). Both need a reporting
      channel; decide it before writing them.
- [ ] **Dependency updates** for GitHub Actions.
- [ ] **CI to the reference's bar:** pin every action by commit SHA with a version
      comment; add pre-commit hooks (whitespace and end-of-file, YAML and JSON
      validity, large files, private-key detection, shellcheck, markdownlint) and
      run them in CI; add a secret scan; keep least-privilege permissions and
      concurrency groups.

### C. Release automation

- [ ] **A version source.** A `VERSION` file that `dss-lab --version` prints and
      the release tooling keeps in step, with Commitizen configured in `.cz.toml`
      (a bash project does not otherwise need `pyproject.toml`).
- [ ] **Enforce Conventional Commits:** a commit-message hook, and a PR-title check
      that validates the squash-merge title.
- [ ] **A bump workflow:** on a merge to `main`, derive the version from the
      commits, update `VERSION` and `CHANGELOG.md`, tag `vX.Y.Z`, and publish the
      release with the new changelog section as its notes. Fail before tagging if
      the version files disagree.
- [ ] **Seed the baseline tag.** The changelog already describes `0.1.0`, but no
      tag exists. Tag the first release by hand with a hand-written entry, then
      let the automation take over.

> **Risk to resolve first.** The reference pushes its version-bump commit straight
> to `main` with the default workflow token. With `main` protected, that push is
> refused. Options: a repository ruleset that lists the Actions integration as
> a bypass actor (preferred); have the workflow open a bump pull request instead;
> or use a scoped token. Settle this before turning on both protection and
> automation, or every release will fail at its last step.

### D. Agent plugin

- [ ] **Rework the skills** so they find the CLI from their own location (the
      skills live at `skills/<name>/`, so `bin/dss-lab` is two levels up) instead
      of relying on `make install` substituting a path. Keep `make install` as a
      fallback, and keep the docs-consistency test green.
- [ ] **Plugin manifests** for Claude Code and Codex, and a marketplace entry, with
      the version kept in step with `VERSION` by the release tooling.
- [ ] **README install section** for each supported agent, plus the universal
      skills install.
- [ ] Test an install from the published repository, not from a working copy.

### E. Product quality before and after launch

Before launch, because they protect users:

- [ ] **Finish the licence read-back gate.** `dsscli set-license` exits 0 for a
      licence the node cannot parse, so today the only protection is skipping the
      2025-tier licences below 12.6.0. Confirm success by reading the licensing
      status back. That needs an API key, which `provision` creates after the
      licence, so the order has to change with care. The same change fixes a
      leftover licence copy in the container's `/tmp`.
- [ ] **Guard the Docker VM's disk.** During the boundary builds the build cache
      reached 55 GB on a 160 GB VM and had to be pruned by hand. `doctor` and
      `build` should check free space first and point at `gc`.

After launch, as the next milestone:

- [ ] **Seed with realistic content** ([roadmap](ROADMAP.md) phase 7). Import real
      project exports with `dss-lab bundle`, upgrade them across versions, and
      record what breaks. This is the largest gap between what the matrix claims
      and what it shows.
- [ ] **Automate the matrix.** A `verify` command that builds or pulls a version,
      provisions it, probes the licence tiers, measures idle memory and cleans up,
      printing one matrix row. Only 14 of the 109 versions have been run. It
      would also flag a first boot far slower than its neighbours
      ([known issue K14](KNOWN_ISSUES.md)).

### F. Publishing

Last, and in this order:

- [ ] **Publish from clean history.** Older commits contain files that no longer
      exist, some embedding local paths. Recreate the repository, or have the host
      purge the old history, rather than relying on a force-push: the host may keep
      old commits reachable by hash for a while.
- [ ] **Commit author identity.** Decide the name and address the public commits
      carry, and set it before the history to be published is created.
- [ ] **Repository settings:** a ruleset protecting `main` (pull request and
      passing CI required, squash merges only, delete merged branches, an
      administrator bypass), private vulnerability reporting on, a description and
      topics.
- [ ] **Turn on the release automation**, cut the first release, and check that
      the tag, the changelog entry and the GitHub release all appear.
- [ ] **Change visibility.**

## Pull request checklist

The template will ask for these, adapted from the reference:

- [ ] The change is limited to its stated scope
- [ ] The PR title follows Conventional Commits
- [ ] Tests pass: `bash tests/run_tests.sh`
- [ ] `shellcheck` and `markdownlint` pass
- [ ] Docs updated where commands, output or behaviour changed
- [ ] No licence file, credential, instance URL or customer data is included

## Still open

- **Reporting channel** for the security policy and code of conduct.
- **The first version number.** The changelog says `0.1.0`; the unreleased work
  suggests `0.2.0`.
- **How the bump commit reaches a protected `main`** (the risk above).
- **Whether the plugin should also carry the seeding tools**, or only the three
  lifecycle skills it has today.
- **Intel Mac and Linux support**, which is optional: there is no emulation cost
  there, but the code assumes Docker Desktop on macOS in a few places.

## Done means

A stranger can find the repository, install it as a plugin or by cloning, follow
the README with their own licences, provision any version the matrix lists, and
get the results the matrix reports. Every merge is a reviewed pull request with
green CI, releases appear on their own with an accurate changelog, and nothing in
the tree refers to people or systems they cannot see.
