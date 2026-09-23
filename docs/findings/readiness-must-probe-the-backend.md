# Readiness: nginx answers long before DSS does

**Date:** 2026-09-03
**Status:** verified, bug found and fixed
**Corrects:** the boot timings in
[provisioning-chain-verified](provisioning-chain-verified.md) and
[built-image-verified](built-image-verified.md)

## The bug

`instance_wait` polled `GET /` and treated any 2xx/3xx as ready. That is a
**false positive**: nginx starts and serves the DSS login page while the backend
is still coming up.

Found the hard way. `dsscli set-license` ran immediately after the "ready"
signal and died with:

```text
ConnectionRefusedError: [Errno 111] Connection refused
HTTPConnectionPool(host='127.0.0.1', port=10001):
  Max retries exceeded with url: /dip/publicapi/admin/licensing/license
```

**`dsscli set-license` is not a filesystem operation.** It is a REST client
posting to the DSS backend on `:10001`. So are the other `dsscli` subcommands.
Every one of them needs the backend, not just nginx.

## Measured

Fresh `dss-mac-docker/dss:12.6.7` container, polled every 10s:

| t | `GET /` | `GET /public/api/admin/licensing/status` |
| --- | --- | --- |
| 10-40s | 000 (nothing listening) | 000 |
| **50s** | **200** | **502** ← nginx up, backend down |
| 60s | 200 | 401 ← backend ready |

There is a real window — at least 10 seconds, and longer on a loaded host —
where the old probe reported success and anything touching DSS would fail.

## The fix

Probe an API path proxied to the backend, and read the status codes for what
they mean:

- `502` / `503` / `504` — nginx is up, backend is **not**. Keep waiting.
- `401` — the backend answered and demanded credentials. **Ready.**
- `200` / `403` — also ready.

```bash
DSS_READY_PATH="/public/api/admin/licensing/status"
```

401 is the signal to wait for, which reads oddly but is correct: an
authentication challenge can only come from a backend that is running.

Verified after the fix: `up 12.6.7` reported ready at 50s having logged "nginx
is up; waiting for the backend", and `set-license` then succeeded immediately —
the exact sequence that failed before.

## Corrections to earlier findings

Both earlier documents reported boot times measured with the broken probe. They
were measuring **nginx**, not DSS:

| Claim | Was | Actually |
| --- | --- | --- |
| 12.6.4 pulled, "up after 25s" | nginx at 25s | backend later |
| 12.6.7 built, "boots in 35s" | nginx at 35s | backend ~50-60s |

The order-of-magnitude conclusion still holds — first boot is about a minute,
not the ten-plus minutes originally predicted — but the specific figures were
optimistic by roughly 15-25 seconds.

## Why it went unnoticed at first

The first `set-license` on 12.6.4 succeeded because minutes had passed between
booting the container and running it — enough for the backend to come up on its
own. The bug only surfaced when the same steps ran back to back, which is
exactly how the automated provisioning flow will run them.

A latent race that only appears under automation is the worst kind to ship into
a machine-to-machine interface.
