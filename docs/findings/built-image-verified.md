# A built (non-Hub) version runs, licenses and provisions identically

**Date:** 2026-09-03
**Status:** verified
**Covers:** ROADMAP phase 3 · the open question left by
[provisioning-chain-verified](provisioning-chain-verified.md)

## What was built

`dss-lab build 12.6.7` — a version Docker Hub does not publish, chosen because
it is the newest 12.x and sits one patch above the era's base image.

```text
BASE_IMAGE=dataiku/dss:12.6.4   (already local — no extra pull)
DSS_VERSION_ARG=12.6.7
PUPPETEER_VERSION=13.7.0        (dss11-12 era pin)
→ dss-mac-docker/dss:12.6.7
```

Labels recorded on the image: `version=12.6.7`, `era=dss11-12`,
`base=dataiku/dss:12.6.4`, `managed=true`.

## The kit swap works

Build success proves nothing on its own — the question is whether the container
runs the *new* kit or the base's. It runs the new one:

| Check | Result |
| --- | --- |
| `DKUINSTALLDIR` in the datadir | `/home/dataiku/dataiku-dss-12.6.7` |
| `DSS_VERSION` in the image | `12.6.7` |
| DSS `dss-version.json` | `"product_version": "12.6.7"` |
| Boot time | 35s to nginx; **~50-60s to a usable backend** (see note) |

Setting `ENV DSS_VERSION` is what redirects the inherited `run.sh` onto the new
install directory, and it holds.

> The 35s figure was measured with a readiness probe that watched nginx rather
> than the DSS backend, and is therefore optimistic. See
> [readiness-must-probe-the-backend](readiness-must-probe-the-backend.md).

**The predicted dead-kit cost is real**: both `dataiku-dss-12.6.4` and
`dataiku-dss-12.6.7` are present on disk. The base's kit sits in a lower layer,
so removing it reclaims nothing. That is the documented trade for skipping the
emulated R build (DESIGN D3), and it is shared across every version built on
that base.

## Provisioning behaves identically to a pulled image

Same chain as the pulled 12.6.4, same results:

- `dsscli set-license /tmp/license.json` → exit 0
- `dsscli api-key-create --admin true --output json` → 32-char key
- admin licensing endpoint with the key → **200**, `expiresOn` 2026-09-29,
  `community: False`

So a built image is not a second-class citizen; the phase-4 flow does not need
to branch on how the image was obtained.

## Side by side

```text
VERSION    CONTAINER      STATE      PORT    SOURCE  URL
12.6.4     dss-12.6.4     running    11640   pull    http://localhost:11640
12.6.7     dss-12.6.7     running    11670   build   http://localhost:11670
```

Two versions of the same DSS line, concurrently, on formula-derived ports, with
no collision and no configuration.

## Memory: the D7 measurement

Measured with both instances running (VM raised to 10 GB):

| Container | Memory | CPU |
| --- | --- | --- |
| `dss-12.6.7` (just booted) | 1.48 GiB | 321% (settling) |
| `dss-12.6.4` (idle) | 1.98 GiB | 4.5% |

**A DSS 12.x instance idles at roughly 2 GiB.** On a 10 GB VM that is about four
concurrent instances, not the "one at a time" K1 predicted.

Consequence: **the `env-site.sh` heap tuning in DESIGN D7 is not needed at this
scale** and should stay unimplemented until something actually demonstrates
memory pressure. Guessing a smaller heap would slow DSS down to solve a problem
that does not exist.

Unmeasured: 14.x/15.x, which are larger images and may idle higher; and DSS
under real load rather than idle.

## Loose end

The per-container limit is set to `VM memory − 1 GiB`, which is a sane ceiling
for one instance but is not meaningful protection once several run — two
containers each capped at 9 GiB on a 10 GB VM can still contend. Given measured
idle use of ~2 GiB the ceiling is not the real safeguard; the warning when
starting an additional instance is. Left as-is rather than picking an arbitrary
lower cap that might OOM-kill legitimate work.
