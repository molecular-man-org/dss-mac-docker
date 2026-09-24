# Known issues and risks

Ordered by how likely they are to cost real time. Anything marked **UNVERIFIED**
is an assumption that has not been tested — treat it as a task, not a fact.

---

## K1. Docker VM memory — largely resolved 2026-09-03, and it was overstated

The VM has since been raised to **10 GB** and real usage measured
([finding](findings/built-image-verified.md)): a DSS **12.x** instance idles at
roughly **2 GiB**. Two ran comfortably side by side; about four would fit.

The original claim — "one modern instance at a time" — was a guess from
upstream's 32 GB production figure and was **too pessimistic**. The
`env-site.sh` heap tuning it motivated (DESIGN D7) is correspondingly
unnecessary and should stay unimplemented until something demonstrates real
pressure.

Still open: **14.x/15.x are unmeasured** and are much larger images, so they may
idle higher. Measure before assuming they behave like 12.x.

Going above ~10 GB on a 16 GB host starves macOS. `doctor` recommends but never
silently changes it — the setting needs a Docker Desktop restart.

## K2. Everything runs under Rosetta emulation

DSS is x86-64 only (RESEARCH §2). All Docker operations need
`--platform linux/amd64`; without it Docker will refuse or warn on an arm64 host.

Consequences: first boot is slow — `installer.sh` plus R integration plus
graphics export, all emulated. `wait` must poll HTTP with a generous timeout
(start at 30 min for first boot) rather than appearing to hang.

**Partly resolved 2026-09-03:** emulation itself is proven — an amd64 container
ran and reported `x86_64` via `doctor --deep`
([finding](findings/rosetta-amd64-verified.md)).

**Still UNVERIFIED:** that *DSS* boots under emulation. A static `uname` binary
proves nothing about a JVM, R, Python and nginx running together for minutes
under memory pressure. Phase 5 still spot-checks each era plus the boundary
versions 11.4.5, 12.6.7, 13.5.7, 14.7.3.

## K3. `run.sh` upgrades datadirs irreversibly, with no prompt

Point a 14.x container at a 13.x volume and it migrates: `rm -rf pyenv` then
`installer.sh -u -y`. There is no downgrade path (RESEARCH §7).

Guard: `up` compares the volume's `version` label against the request and refuses
without `--migrate`; `upgrade` migrates a clone and leaves the source untouched
(DESIGN D5). **This is the single
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

## K6. Skill installation — RESOLVED 2026-09-03

Sidestepped rather than tested. `make install` **copies** each skill into
`~/.claude/skills/` and substitutes the absolute CLI path into the `SKILL.md` as
it goes, so nothing depends on whether Claude Code follows symlinks, and the path
stays correct even if the repo moves.

Cost: `make install` must be re-run after editing anything under `skills/`. The
Makefile target says so, and it is idempotent.

## K7. Java 8 recipe against late 12.x — RESOLVED 2026-09-23

12.6.7 was built from this recipe and boots, licenses and provisions; 12.4.2 was
built the same way. The original reasoning is kept below.

The 11.x-12.x era uses `java-1.8.0-openjdk` and `python36`. Evidence it works for
late 12.x is that Dataiku built the `12.6.4` Hub image from that recipe in July
2024 (RESEARCH §6). That is good but indirect. **Spot-check 12.6.7 specifically**
before trusting the whole 12.x line.

## K8. `base_dss` tarball semantics unresolved

Whether `container-images/dataiku-dss-ALL-base_dss-*.tar.gz` is a full DSS server
or a containerized-execution base image is **UNVERIFIED** and unresolvable
without a 5.4 GB download (RESEARCH §5). Deliberately out of scope. Reopen only
for an air-gapped workflow.

## K9. Docker daemon was not running during research — RESOLVED 2026-09-03

The socket did not exist when this repo was planned, so the phase-1 code was
written from the documented contract rather than observed behaviour.

The daemon has since been up: `doctor` was exercised in both states (down →
blocking, with the `open -a Docker` hint; up → passing) and `doctor --deep` ran
a real container. Phase-1 docker interaction is no longer theoretical.

Still true for **phase 2 onward** — nothing has yet pulled, built or run a DSS
image. Treat the first `up` as a bring-up.

## K10. Which licence offer strings older DSS accepts — MEASURED 2026-09-23

The 2025 tiers are rejected below 12.6.0 (11.2.0 and 12.4.2 measured) and accepted
from 12.6.4 on; 2024 and 2018 are accepted everywhere tested. See the
[matrix](compatibility-matrix.md). The original analysis is kept below.

The five available licences differ by feature tier, not DSS version
(PROVISIONING §"Choosing the appropriate licence"). Tim's direction is to try
`dev-*-2024.json` (offer `enterprise-fy2023-1`) first, on the reasoning that an
older offer string is likelier to be understood by DSS 12.x than a 2025 one.

**Partly settled 2026-09-03:** `dev-*-2024.json` was accepted first try on both
a pulled 12.6.4 and a built 12.6.7. The fallback walk has therefore **never been
exercised against a real rejection**, and 13.x/14.x/15.x are untested.

**The rest is still hypothesis, not measured fact.** Treat licence rejection as
an
expected outcome: `provision` walks the preference order until one is accepted
rather than failing on the first rejection, and reports which one won. Record
the results per era — that table is the real answer.

## K11. Licences carry an `instanceId` — RESOLVED, does not block

Every licence names an instance id. If DSS validates it against its own instance
id, a freshly-installed container may reject all five and the whole provisioning
flow stops at step 3.

Cheap to settle as soon as one container boots. Settle it early — it invalidates
the design if it goes the wrong way.

## K12. `~/.dataiku/config.json` holds live production credentials

The handoff registers instances into the user's real `dataiku-headless` config,
which already contains API keys for production and sandbox instances
(production and sandbox nodes).

**A careless write destroys the user's working credentials.**

**Implemented and verified 2026-09-03** — checked against a fingerprinted
snapshot of the real file: 6 instances became 7, none lost, none modified, every
API key fingerprint preserved, `default_instance` untouched
([finding](findings/provisioning-flow-verified.md)).

`register_instance` backs up first, refuses to write if the existing file will
not parse, refuses to write if any existing instance name would disappear,
writes atomically at mode `0600`, and never touches `default_instance`. Both
protections are mutation-tested in `tests/run_tests.sh`.

## K13. Licences expire

Licence files carry an `expiresOn`. When the ones you supply lapse,
provisioning breaks for every version at once and the failure will look like a
DSS bug rather than an expiry.

**Implemented 2026-09-03.** `provision` skips expired candidates with a warning
and refuses outright if every one has lapsed. Below 30 days it warns.

## K14. A mismatched Puppeteer pin made first boot take 11 minutes — RESOLVED

On first boot `run.sh` runs the kit's `install-graphics-export`, which chooses a
Puppeteer version from the image's Node.js version, in a table that differs
between kits. The image pre-installed an era-wide pin (13.7.0 for 11.x and 12.x);
12.5.2's kit wants 21.3.6, so npm re-downloaded Puppeteer and Chromium under
emulation: `added 71 packages ... in 10m`, and a 650s first boot. It is
reproducible, and nothing failed — `provision` simply took eleven minutes.

Fixed 2026-09-23: `docker/kit-puppeteer.sh` evaluates the kit's own selection
block against the image's Node during the build, and the Dockerfile pre-installs
that version, keeping the era pin only as a fallback. 12.5.2 then booted in 35s.
The risk is any kit whose selection block is not recognised: it falls back to the
era pin and can be slow on first boot again, which is worth checking if a version
takes minutes to first answer.
