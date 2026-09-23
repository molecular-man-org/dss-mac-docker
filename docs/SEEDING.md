# Seeding provisioned instances

A freshly provisioned DSS instance is **empty**, which makes it a weak target for
upgrade assessment — there is almost nothing to scan. Seeding creates content
chosen for **structural coverage, not volume**.

The consumer (the upgrade-planning skill) is **strictly read-only**
and never writes to a DSS node. All content creation happens here, and it only reads
what we create. Nothing in this design may expect the consumer to import or
mutate anything.

```bash
dss-lab seed 12.6.7                    # default slice
dss-lab seed 14.7.3 --slice cross-project
```

Idempotent — re-seeding an already-seeded instance creates nothing.

---

## Per-era sparseness is signal, not noise

Object types that do not exist on an older DSS are simply **absent** there.
Agents, semantic models and several other types do not exist on DSS 12 at all.

**Do not normalise the eras.** An older node genuinely having fewer object types
is a true observation about that version, and flattening it would manufacture a
false equivalence between versions — exactly the kind of confident-but-wrong
answer the consumer's project exists to prevent.

This is easy to lose to a well-meaning "make the eras consistent" cleanup later.
It is recorded here so that cleanup does not happen by accident.

## Shapes requested, in the consumer's priority order

Roughly a dozen projects total. Not scale — the consumer already has a synthetic
~3,900-project corpus for volume questions. What synthetic data cannot provide is
the real JSON a live node emits.

| # | Shape | Status |
| --- | --- | --- |
| 1 | Cross-project dataset reference (`<projectKey>.<datasetName>`) | **done** |
| 2 | Code envs bound at project **and** recipe level, incl. an `EXPLICIT_ENV` recipe override | **done** |
| 3 | A `cpython` recipe and one CustomCode-family recipe | **partial** — `cpython` done, CustomCode blocked |
| 4 | Projects with **and without** an explicit lifecycle status | to do |
| 5 | Job/scenario history with varied recency (inside and outside 180 days) | to do |
| 6 | Duplicate-family keys: `COPYOF_`, `_v2`, numeric/timestamp/person suffixes | to do |
| 7 | Tutorial prefixes: `TUT_`, `DKU_TUTORIAL`, and `QS_` | to do |

Items 1-3 were called out as unblocking more than the rest combined.

## Slice 1 — cross-project dataset reference `[done]`

The consumer's highest-value item. Its `detect_cross_project_dependencies()` and
the scope rule elevating a depended-on project to `REVIEW` had never run against
a real node — the rule was written but not enforced, silently leaving
dependencies at `EXCLUDE`.

Creates:

```text
SEED_SHARED_REF                    project
  └── customers                    managed filesystem dataset, 4-column schema
SEED_CONSUMER                      project
  ├── customers_local              managed filesystem dataset
  └── sync_customers_from_shared   sync recipe
        input:  SEED_SHARED_REF.customers   ← the foreign reference
        output: customers_local
```

Verified on both eras — the stored recipe carries the input ref exactly as the
convention requires:

```text
dss-12.6.7   type=sync  inputs=['SEED_SHARED_REF.customers']  foreign-ref=YES
dss-14.7.3   type=sync  inputs=['SEED_SHARED_REF.customers']  foreign-ref=YES
```

Read it back at `GET /public/api/projects/SEED_CONSUMER/recipes/sync_customers_from_shared`
— note the response wraps the object as `{"recipe": {...}}`.

## Slice 2 — code env bindings `[done]`

The binding key is **spelled differently at each level**. This is real DSS
behaviour, not a misreading, and it is a defect area for the consumer — it
shipped a fix for reading `mode` where the recipe level uses `envMode`.

| Level | Path | Key |
| --- | --- | --- |
| Project | `settings.codeEnvs.python` | **`mode`** |
| Recipe | `params.envSelection` | **`envMode`** |

Creates a `seed_py_env` PYTHON code env (`DESIGN_MANAGED`), a `SEED_CODEENV`
project bound to it at project level, and two python recipes — one overriding to
`EXPLICIT_ENV`, one left at `INHERIT` — so overridden and inherited are visible
on the same flow.

Verified identically on both eras, which is the point: the shape is confirmed
*across versions*, not from one node.

```text
12.6.7  PROJECT key='mode'    {"mode":"EXPLICIT_ENV","preventOverride":false,"envName":"seed_py_env"}
12.6.7  RECIPE  key='envMode' {"envMode":"EXPLICIT_ENV","envName":"seed_py_env"}
12.6.7  RECIPE  key='envMode' {"envMode":"INHERIT"}
14.7.3  (identical on all three)
```

Note DSS also writes `containerSelection.containerMode` alongside — the same
`*Mode` suffix pattern at recipe level. Worth knowing if anything greps for
`mode` generically.

A recipe's `params` is **null until something sets it**. An unset code recipe
does not report `envMode: INHERIT`; it reports nothing at all. A collector
treating absent-params as "no env configured" versus "inherits" would be making
a distinction DSS does not store.

## Slice 3 — non-canonical recipe types `[partial]`

**`cpython` — done.** DSS accepts it as a recipe type distinct from `python`,
and it persists as `type=cpython` on both 12.4.2 and 14.7.3. Seeded in
`SEED_RECIPETYPES.compute_out_cpython`.

Probed while establishing this: `cpython`, `python`, `r`, `shell` and `pyspark`
are all accepted directly. `sql_query` is rejected for a filesystem input, which
is a dataset-compatibility rule rather than an unsupported type.

**CustomCode — blocked, and deliberately not faked.** A `CustomCode_*` type needs
a plugin that actually provides a recipe, and none of the seven built-in plugins
do.

Progress made, so the next attempt does not start over:

1. `POST /plugins/actions/createDev` **exists** — it returns 500, not 404, and
   names the missing field: `DevPluginBootstrapMode.mode` is null. Six guesses at
   the enum (`EMPTY`, `RECIPE`, `PYTHON_RECIPE`, `CUSTOM_RECIPE`, `DATASET`,
   `BLANK`) all failed. **Stop guessing** — find the real values.
2. The **filesystem route works**. A dev plugin written to
   `$DSS_DATADIR/plugins/dev/<id>/` and followed by a container restart is
   registered: `seedcustomcode` now shows `isDev: true` on `dss-14.7.3`. A cache
   invalidate alone is **not** enough — it needs the restart.
   The plugin source is checked in at `seed/plugin/seedcustomcode/`.
3. **What blocks it:** creating the recipe returns
   `Could not parse a RecipeCreationInfo from request body` — a *parse* failure,
   not an unknown type, so the body shape is wrong rather than the plugin being
   unregistered. The same body works for `type: python`. The untested variable is
   the custom input/output role names (`input_ds` / `output_ds` instead of
   `main`).

Next step: find how the SDK constructs a plugin-recipe creation body — the
installed client has no `CustomCode` references, so it is likely elsewhere in
the SDK or only in the UI's own calls.

## How it works

`seed/dss_seed.py` talks to the DSS public API over HTTP basic auth (API key as
username, empty password), using only the standard library so there is no
dependency on a client version that may not match the target DSS.

`dss-lab seed` resolves the version, reads the recorded API key from
`~/.dataiku/config.json`, and requires the instance to be running.

## Evidence quality: `deps_check`

Old DSS kits reject newer point releases of the base OS. `almalinux:8` floats and
now resolves to **8.10**; DSS 12.4.2 predates it and aborts with
`*** OS distribution not supported *** almalinux 8.10`, while 12.6.4 on the same
OS is fine. The dependencies are genuinely present — the base image runs its own
DSS — only the version-string check is wrong.

Pinning the base OS would be the cleaner fix, but is not available here: the Hub
base **is already 8.10**, so pinning means abandoning the Hub-base strategy
for a
from-scratch build and paying the emulated R compile (DESIGN D3).

So such builds pass `-n` / `-noDeps` to the installer and the two `dssadmin`
steps, and are **marked**:

```json
{ "version": "12.4.2", "deps_check": "skipped", ... }
```

`normal` for a pulled Hub image or a build that needed no patching; `skipped`
otherwise. Recorded as an image label, propagated to the container label, and
returned by `provision`.

**Why it matters for anyone citing an instance as evidence:** with checks
skipped, a genuinely missing library could make a capability look *absent* when
it is really present-but-broken — a false absence, invisible at the point of
observation.

The caveat is weaker for **route-existence** claims than for functional ones.
A 404 from an unregistered REST route is a routing fact; a missing Python
library does not unregister a route. It matters much more for "this capability
works" than for "this endpoint exists".

## Working constraints

- **Two instances at a time**, with teardown between batches. Do not size this
  work around a parallel sweep across many versions.
- Currently seeded: **12.6.7** and **14.7.3**. 12.x is the oldest version the
  consumer assesses, and the era where its capability matrix makes the most
  unverified "not available" claims.
