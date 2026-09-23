# DSS 13.x masks API key secrets; 12.x does not

**Date:** 2026-09-03
**Status:** bug found and fixed
**Severity:** would have handed the calling agent a non-working credential

## The bug

`apikey_ensure` reused an existing key by reading `dsscli api-keys-list
--output json` and taking its `key` field. On DSS 13.5.7 that field is
**`******`** — six asterisks. The masked placeholder was stored in
`~/.dataiku/config.json` as a credential and returned in the provisioning JSON.

```text
dss-12.6.4     key length=32
dss-12.6.7     key length=32
dss-13.5.7     key length=6     ← "******"
dss-14.7.3     key length=39
```

The consumer would have received a well-formed JSON response, connected, and
got **401**. `provision` exited 0 throughout.

## Why it escaped the earlier verification

12.x **does** disclose the secret in `api-keys-list`, so the reuse path was
exercised and passed on 12.6.4 and 12.6.7. 14.7.3 stored a valid 39-char key
because that came from the *mint* path on a first provision — its reuse path had
never run. The defect needed a version that masks **and** a second provision.

Key lengths also differ by line: **32 chars on 12.x, 39 on 13.x and 14.x.**
Nothing should assume a length.

## A second defect found alongside it

`dsscli` writes a log line to **stdout**, ahead of the JSON, on its first
invocation in a container:

```text
[2026-09-03 20:54:42,573] [INFO] [dsscli] Creating an admin key for dsscli
[{"id": "...", "key": "...", "label": "dss-mac-docker", "admin": true}]
```

`json.load` fails on that. It did not bite 12.x because those containers had
already bootstrapped their dsscli key during earlier manual testing. Parsing now
skips to the first `[` or `{`.

## The fix: trust use, not listings

A listing cannot be trusted to disclose a secret, so the key is validated by
**actually calling the API with it**. Order:

1. **The key we recorded ourselves** in `~/.dataiku/config.json` — the only place
   the plaintext is guaranteed to survive — confirmed with a live request.
2. A listing, but only if the value passes `apikey_valid` **and** authenticates.
3. Mint a fresh key, then verify *that* authenticates before returning it.

`apikey_valid` rejects anything empty, containing `*`, or shorter than 16 chars.
`provision` now fails loudly rather than returning a key that does not work.

## Known residue

`dsscli api-key-delete` takes the **secret**, not the id:

```text
usage: dsscli api-key-delete [-h] key
    key    Secret key of API key to delete
```

So a masked key **cannot be deleted programmatically** — its secret is exactly
what is unavailable. `dss-13.5.7` therefore carries one orphaned key from before
the fix. It does not grow: reuse now comes from the config, so a working instance
mints at most once. Cleaning up an orphan requires the DSS UI.

## Lesson

Both the earlier readiness race and this one share a shape: **a step reported
success while producing something unusable**, and only a second, differently-timed
run exposed it. For a machine-to-machine interface, "exit 0 and well-formed
output" is not evidence of a working result. Verify the artefact by using it.
