---
name: start-dss-container
description: Start or create a local Dataiku DSS instance of a specific version in Docker on macOS. Use when the user asks to start, create, spin up, launch or provision a DSS instance or container for a version (e.g. "create a new instance of DSS v12.3.0", "start DSS 14", "/start-dss-container 12.6.4"). Also use when another agent needs a DSS instance provisioned for testing.
---

# Start a DSS container

Run `__DSS_LAB__ up <version>`. It is idempotent — an existing container is
simply started, an absent one is created. **It never prompts, so do not ask the
user to confirm anything.**

## Steps

1. **Extract the version** from what the user said. Pass it through verbatim;
   the CLI resolves fuzzy forms itself:

   | User says | Pass |
   | --- | --- |
   | "DSS v12.3.0", "12.3.0" | `12.3.0` |
   | "DSS 12.3" | `12.3` (→ newest 12.3.x) |
   | "DSS 14", "latest 14" | `14` (→ newest 14.x) |
   | "latest DSS" | `latest` |

   If no version is given at all, ask which one — that is the only question
   worth asking. `__DSS_LAB__ catalog` lists what is available.

2. **Run it:**

   ```bash
   __DSS_LAB__ up <version>
   ```

3. **Report the URL** from the output, e.g. `http://localhost:11640`.

## What to expect

- A version not on Docker Hub is **built** — 95 of the 109 supported versions
  are. That takes several minutes.
- **First boot is slow.** DSS is x86-64 only, so it runs emulated under Rosetta,
  and the first start runs the installer plus R integration. Ten minutes or more
  is normal; the command waits and reports progress. Do not assume it has hung.

## If it refuses

- **"datadir was written by DSS X, not Y"** — the intentional guard against an
  irreversible in-place migration. Do **not** re-run with `--migrate` on your
  own; tell the user what it means and let them decide.
- **"Docker daemon is not running"** — run `open -a Docker`, wait, retry.
- **Unknown version** — the error lists nearby versions; offer those.

## Related

`__DSS_LAB__ ls` lists instances · `stop <version>` stops one ·
`rm <version>` deletes one and its data.
