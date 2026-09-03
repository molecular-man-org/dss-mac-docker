# Rosetta amd64 emulation works on this host

**Date:** 2026-09-03
**Status:** verified
**Closes:** most of [KNOWN_ISSUES](../KNOWN_ISSUES.md) K2, and all of K9

## Claim under test

DSS ships x86-64 only (RESEARCH §2), so every container on this arm64 Mac runs
emulated. The design assumed Rosetta would carry that, based only on
`UseVirtualizationFrameworkRosetta: true` in Docker Desktop's settings store.
A settings flag is not evidence that emulation actually executes.

## Method

`dss-lab doctor --deep` runs a real amd64 container and reads back its
architecture:

```bash
docker run --rm --platform linux/amd64 alpine:3 uname -m
```

## Result

```text
x86_64
```

An amd64 binary executed and self-reported as x86-64 under emulation.

## What this does and does not establish

**Established:** the emulation path works end to end — `--platform linux/amd64`
is honoured, the image is fetched for the right architecture, and amd64 user
space runs.

**Not established:** that DSS itself boots under emulation. Alpine's `uname` is
a trivial static binary. DSS exercises a JVM, R, Python and nginx together, for
minutes, under memory pressure. The per-era boot checks in ROADMAP phase 5
remain necessary and K2 stays open for that reason.

## Incidental findings

The Docker daemon was **not** running during the research phase, which is why
every docker invocation in this repo was written from the documented contract
rather than observed behaviour (K9). The daemon was up for this check, so
`doctor` has now been exercised against a live daemon in both states — daemon
down (reported as blocking, with the `open -a Docker` hint) and daemon up.

`docker system df` at the time reported 14.97 GB of images with 12.89 GB
reclaimable — worth knowing before the first DSS pull, given the ~60 GB VM disk
and ~9-11 GB per modern DSS image (K4).
