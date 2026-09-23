# dss-mac-docker — notes for Claude sessions

Read this first; it holds the facts that are easy to get wrong.

## Licences

Full reference: [docs/LICENCES.md](docs/LICENCES.md). The essentials:

- **Licence files live in `~/.dataiku/licenses/`.** This is the repo standard,
  the default of `DSS_LAB_LICENSE_DIR`, and what new users are told to use. Never
  copy a licence file into the repo, and never commit one.
- **Match the licence type to the DSS version and package era.** Canonical
  maximum-productive-access profile per type:

  ```text
  2025 -> FULL_DESIGNER    (requires DSS 12.6.0 or later)
  2024 -> DESIGNER         (FY2021-FY2024 packages; the default)
  2018 -> DATA_SCIENTIST   (legacy profiles; old instances only)
  ```

- **The three "2025" licences must not be used on DSS older than 12.6.0.** Older
  DSS rejects them, and `dsscli set-license` can still exit 0.
- **"Maximum access" means the top productive designer profile, never an
  administrative one.** Do not use `PLATFORM_ADMIN`, `ADMIN` or
  `TECHNICAL_ACCOUNT` to get more features; admin rights are assigned separately.

## Working rules

- Local Docker DSS nodes may be changed freely; internet-hosted DSS nodes never.
- Run at most two DSS nodes at once (the Docker VM's memory is the limit).
- `bash tests/run_tests.sh` needs no Docker; `markdownlint .` and `shellcheck` run
  in the same gate.
