# Known issues and risks

Ordered by how likely they are to cost real time. Anything marked **UNVERIFIED**
is an assumption that has not been tested — treat it as a task, not a fact.

---

## K1. Docker VM has 6.25 GB RAM — the binding constraint

DSS 14/15 assumes far more (upstream asks 32 GB for production). Expect to run
**one modern instance at a time**, despite side-by-side being a wanted workflow.

Mitigations: reduced backend heap written at first boot (DESIGN D7); `up` warns
and names candidates to stop when running instances exceed a memory budget.

Raising the VM to ~10 GB is reasonable on a 16 GB host. Going higher starves
macOS. `doctor` should recommend but never silently change it — it requires a
Docker Desktop restart.

## K2. Everything runs under Rosetta emulation

DSS is x86-64 only (RESEARCH §2). All Docker operations need
`--platform linux/amd64`; without it Docker will refuse or warn on an arm64 host.

Consequences: first boot is slow — `installer.sh` plus R integration plus
graphics export, all emulated. `wait` must poll HTTP with a generous timeout
(start at 30 min for first boot) rather than appearing to hang.

**UNVERIFIED:** that every era actually boots under Rosetta. Risk is low —
everything in range is 2022+ on AlmaLinux 8/9 with Java 8 or 17 — but it is
unmeasured. Phase 5 spot-checks each era plus the boundary versions 11.4.5,
12.6.7, 13.5.7, 14.7.3.

## K3. `run.sh` upgrades datadirs irreversibly, with no prompt

Point a 14.x container at a 13.x volume and it migrates: `rm -rf pyenv` then
`installer.sh -u -y`. There is no downgrade path (RESEARCH §7).

Guard: `up` compares the volume's `version` label against the request and refuses
without `--migrate`; `upgrade` snapshots first (DESIGN D5). **This is the single
most destructive thing the tool can do** — implement the guard in the same change
as `up`, never after.

## K4. Disk fills fast

~60 GB VM disk; modern images are ~9-11 GB unpacked. One container per version
plus 109 reachable versions is a lot of latent disk.

Era-base layer sharing helps a great deal — versions within an era share their
whole base. `gc` needs to be genuinely useful: dangling images, stopped
containers, orphaned volumes, with sizes shown. `doctor` refuses a pull or build
that would exhaust the disk.

## K5. Build path is the majority path

Only 14 of 109 in-range versions exist on Hub (RESEARCH §3). Anything that makes
building slow or unreliable hits ~87% of use. The two-stage build (DESIGN D3) is
load-bearing, not an optimization.

## K6. Symlinked skills — UNVERIFIED

`make install` symlinks skill directories into `~/.claude/skills/`. Whether
Claude Code follows symlinks there has **not been tested**. Fall back to copying,
with `make install` re-runnable, if it does not.

`~/.claude/skills/` does not exist yet on this machine; `make install` creates it.

## K7. Java 8 recipe against late 12.x — thinly evidenced

The 11.x-12.x era uses `java-1.8.0-openjdk` and `python36`. Evidence it works for
late 12.x is that Dataiku built the `12.6.4` Hub image from that recipe in July
2024 (RESEARCH §6). That is good but indirect. **Spot-check 12.6.7 specifically**
before trusting the whole 12.x line.

## K8. `base_dss` tarball semantics unresolved

Whether `container-images/dataiku-dss-ALL-base_dss-*.tar.gz` is a full DSS server
or a containerized-execution base image is **UNVERIFIED** and unresolvable
without a 5.4 GB download (RESEARCH §5). Deliberately out of scope. Reopen only
for an air-gapped workflow.

## K9. Docker daemon was not running during research

The socket did not exist when this repo was planned, so **no Docker command in
this repo has been executed against a live daemon yet**. Every docker invocation
is written from the documented contract, not from observed behaviour. Treat the
first real run as a bring-up.
