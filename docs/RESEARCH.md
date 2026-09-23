# Research findings

Everything here was **verified empirically** on 2026-09-03 unless marked
`UNVERIFIED`. Each claim records how it was checked so it can be re-confirmed
cheaply rather than re-derived.

> Re-derivation cost is the reason this file exists. Establishing these facts
> took ~20 network probes and a byte-range download. Do not re-research; verify
> a specific line if you doubt it.

---

## 1. Host and Docker Desktop

| Property | Value | How checked |
| --- | --- | --- |
| Architecture | **arm64** (Apple Silicon) | `uname -m` |
| macOS | 26.6.2 | `sw_vers` |
| Host RAM / CPU | 16 GB / 8 cores | `sysctl hw.memsize hw.ncpu` |
| Host free disk | 269 GB | `df -h /` |
| Docker | 29.7.2 | `docker --version` |
| Docker.app | `/Applications/Docker.app` | `ls` |
| `docker` binary | `/usr/local/bin/docker` → symlink into Docker.app | `ls -l` |

Docker VM settings, from
`~/Library/Group Containers/group.com.docker/settings-store.json`:

| Setting | Value | Consequence |
| --- | --- | --- |
| `Cpus` | 4 | |
| `MemoryMiB` | **6400** (6.25 GB) | Below what DSS 14/15 wants. Main limiter. |
| `SwapMiB` | 3072 | |
| `DiskSizeMiB` | 61035 (~60 GB) | ~4-5 modern DSS images resident |
| `UseVirtualizationFramework` | true | |
| `UseVirtualizationFrameworkRosetta` | **true** | amd64 emulation already enabled |

`Docker.raw` is a 64 GB sparse file at
`~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`.

**The Docker daemon was NOT running** during research — the socket
`~/.docker/run/docker.sock` did not exist. `doctor` must treat this as a
first-class state and offer `open -a Docker`.

## 2. DSS only ships x86-64

<https://doc.dataiku.com/dss/latest/installation/requirements.html> states DSS
"must be installed on a Linux x86-64 server". No arm64/aarch64 build exists.

**Consequence: every DSS container on this Mac runs emulated under Rosetta.**
All Docker operations need an explicit `--platform linux/amd64`.

The same page asks for a minimum of 32 GB RAM. That is a production figure; a
single-user lab instance runs in far less, but it explains why the 6.25 GB VM is
the binding constraint.

## 3. Version availability — the finding that shaped the design

Supported range for this project is **DSS 11.0.0 and later** (11.x is
nice-to-have, 12.x+ is required).

### downloads.dataiku.com — 109 versions in range

`https://downloads.dataiku.com/public/dss/` is an Apache autoindex with 186
version directories total (1.2.0 → 15.0.0). Filtered to 11-15: **109 versions**.
Full list preserved in [`data/versions-11plus.txt`](../data/versions-11plus.txt).

| Line | Versions | Range |
| --- | --- | --- |
| 11.x | 20 | 11.0.0 → 11.4.5 |
| 12.x | 27 | 12.0.0 → 12.6.7 |
| 13.x | 30 | 13.0.0 → 13.5.7 |
| 14.x | 31 | 14.0.0 → 14.7.3 |
| 15.x | 1 | 15.0.0 |

### Docker Hub `dataiku/dss` — only 14 in range

59 tags total (1.4.0 → 15.0.0), **all amd64**. Only **14 fall in the 11+ range**
— preserved in [`data/hub-tags-11plus.txt`](../data/hub-tags-11plus.txt):

`11.2.0`, `12.6.4`, `13.0.0`, `13.4.1`, `13.4.4`, `14.0.0`, `14.2.0`, `14.3.0`,
`14.4.0`, `14.4.1`, `14.5.1`, `14.6.1`, `14.7.0`, `15.0.0` (`latest` = 15.0.0).

Checked via `https://hub.docker.com/v2/repositories/dataiku/dss/tags/?page_size=100`.

> **Hub covers 14 of 109 versions — 13%.** Every line's newest patch (12.6.7,
> 13.5.7, 14.7.3) is missing, as is every 11.x except 11.2.0 and every 12.x
> except 12.6.4.
>
> This is why **build-from-kit is the primary path, not a fallback**. The
> "reproduce a customer's exact patch version" use case depends almost entirely
> on it.

Compressed image sizes grow sharply by era: 2.0.0 = 0.48 GB, 12.6.4 = 3.23 GB,
14.4.0 = 4.19 GB, 15.0.0 = 4.07 GB.

**On-disk expansion measured 2026-09-03: 3.3x, not the 2.2-2.5x first
estimated.** `dataiku/dss:14.7.0` is 3.92 GB compressed and **12.9 GB** on disk.
So budget ~13 GB for a modern DSS image and ~11 GB for a 12.x one. On a ~60 GB
VM disk that is four modern images at the outside, before any datadirs.

## 4. Installer kit URLs — both hosts work

Verified with range requests (`curl -r 0-0`, HTTP 206) for 15.0.0, 14.4.1 and
9.0.7 on **both**:

- `https://cdn.downloads.dataiku.com/public/studio/<V>/dataiku-dss-<V>.tar.gz`
  — the CDN path Dataiku's own Dockerfile uses
- `https://downloads.dataiku.com/public/dss/<V>/dataiku-dss-<V>.tar.gz`

Prefer the CDN path, matching upstream.

## 5. The `container-images/` tarballs — deliberately not used

`https://downloads.dataiku.com/public/dss/<V>/container-images/` holds exactly
one file per version, ~5.1-5.8 GB:

`dataiku-dss-ALL-base_dss-<V>-<os>-r4-py<X.Y>.tar.gz`

- Exists from **12.0.0 onward**. `11.4.5/container-images/` returns **404**.
- The OS/python suffix independently confirms the era boundary in §6:
  12.0.0 / 13.0.0 / 13.5.0 / 13.5.7 → `almalinux8-py3.9`;
  14.0.0 / 14.1.0 / 14.2.0 / 14.4.1 / 14.7.3 → `almalinux9-py3.9`;
  15.0.0 → `almalinux9-py3.12`.
- The server supports byte ranges (`accept-ranges: bytes`, CloudFront-backed).
  A 3 MB range request on the 14.4.1 tarball showed a leading `blobs/sha256/`
  entry, so it is an **OCI-layout `docker save` archive**.

**`UNVERIFIED`: whether `base_dss` is a full DSS *server* image or a
containerized-*execution* base image.** Dataiku's docs never say. Confirming it
means downloading all 5.4 GB, because the tar is a single gzip stream and
`index.json`/`manifest.json` sit at the end — unreachable by range request.

Since Hub + build-from-kit covers all 109 versions, this path is **out of scope**.
Reopen only if an air-gapped workflow needs it.

## 6. Era matrix — from Dataiku's own build recipes

`github.com/dataiku/dataiku-tools`, path `dss-docker/Dockerfile`. Its commit
history maps exactly onto the DSS release lines, so our Dockerfiles are
transcriptions of the recipes Dataiku used to build the Hub images — not guesses.

| Era | Base image | Java | Python | Node | Puppeteer | Source commit |
| --- | --- | --- | --- | --- | --- | --- |
| 11.x - 12.x | `almalinux:8` | `java-1.8.0-openjdk` | `python36` | default | 13.7.0 | `a8fb4d3094` (2022-12-20) |
| 13.x | `almalinux:8` | `java-17-openjdk-headless` | `python39` | `nodejs:20` | 23.11.1 | `b6ab50f2d0` (2025-03-05) |
| 14.x - 15.x | `almalinux:9` | `java-17-openjdk-headless` | `python3` (3.12) | `nodejs:22` | 24.8.2 | `10b8fa9e06` (2025-11-06, master) |

Also: 13.x uses `--enablerepo=powertools`, 14.x+ uses `--enablerepo=crb`.

**Why one recipe covers both 11.x and 12.x:** there is no commit between
`a8fb4d3094` (Dec 2022) and `b6ab50f2d0` (Mar 2025). Dataiku built the `12.6.4`
Hub image in July 2024 — inside that window — so the Java 8 / Python 3.6 recipe
demonstrably works for late 12.x. Still worth a spot-check at 12.6.7.

## 7. The run contract

From upstream `Dockerfile` + `run.sh` (both read in full):

| Property | Value |
| --- | --- |
| Data directory | `/home/dataiku/dss` (`$DSS_DATADIR`) |
| Port | `10000` (`$DSS_PORT`) |
| User | `dataiku` |
| Install dir | `/home/dataiku/dataiku-dss-$DSS_VERSION` |

`run.sh` branches three ways:

1. **No `$DSS_DATADIR/bin/env-default.sh`** → fresh install:
   `installer.sh -d "$DSS_DATADIR" -p "$DSS_PORT"`, then
   `dssadmin install-R-integration`, `dssadmin install-graphics-export`, then
   appends `dku.registration.channel=docker-image` and
   `dku.exports.chrome.sandbox=false` to `config/dip.properties`.
2. **Datadir exists but `$DKUINSTALLDIR` differs** → **in-place upgrade**:
   `rm -rf "$DSS_DATADIR"/pyenv` then `installer.sh -d "$DSS_DATADIR" -u -y`.
3. Otherwise → straight to `exec "$DSS_DATADIR"/bin/dss run`.

> Branch 2 is both the feature that makes upgrade-path testing possible and a
> footgun: pointing a 14.x container at a 13.x volume migrates it irreversibly,
> with no prompt. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Documented run command (Docker Hub):
`docker run -p 10000:10000 -v VOL:/home/dataiku/dss -d dataiku/dss`.
Upstream explicitly calls the image unsuitable for production.

## 8. Upstream Dockerfile has a layer-caching flaw for our use case

Line 5 of every era's Dockerfile:

```dockerfile
ARG dssVersion
ENV DSS_VERSION="$dssVersion" \
    DSS_DATADIR="/home/dataiku/dss" \
    DSS_PORT=10000
```

`ENV DSS_VERSION` sits **above** the `dnf install` and the R package build. So
changing the version invalidates every layer below it — and the R step runs
`install.packages(c('httr','dplyr','ggplot2','sparklyr',...))`, which compiles
C/C++/Fortran from source. Under Rosetta that is the difference between a
~5 minute build and an hour-plus one.

Fix: declare the version ARG *below* the expensive layers. See
[DESIGN.md](DESIGN.md) §"Two-stage build".

## 9. Port formula is collision-free

`port = 10000 + (major - 11) * 1000 + minor * 100 + patch * 10`

Checked against all 109 in-range versions: **109 distinct ports, 0 collisions**,
range 10000-14000. Observed maxima are `minor = 7` and `patch = 7`, so there is
headroom to 9 before adjacent bands would overlap. Guard anyway.

Examples: `11.0.0` → 10000 · `12.3.0` → **11300** · `12.6.7` → 11670 ·
`13.5.7` → 12570 · `14.7.3` → 13730 · `15.0.0` → 14000
