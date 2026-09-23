# Measuring a capability gate: DSS 12.4.2

**Date:** 2026-09-03
**Instance:** `dss-12.4.2` (11420), licensed, seeded, **`deps_check: skipped`**
**Purpose:** 12.4.2 sits above the consumer's 12.3.0 LLM Mesh gate and below its
12.5.0 Knowledge Banks gate, so it can measure a boundary rather than cite one.

## A 403 that nearly became a false finding

The first probe returned **403** for knowledge banks and it looked like a clean
"not available". It was not: `SEED_CONSUMER` did not exist on the instance yet.

The control settles it — capabilities that certainly exist behave identically
against a missing project:

```text
datasets        (known present) -> 403
recipes         (known present) -> 403
knowledge-banks                 -> 403
```

**403 was about the missing project, not the capability.** Probing a
project-scoped endpoint before the project exists measures nothing, and produces
a confident wrong answer. Seed first, then probe — and always carry a control
endpoint whose presence is not in question.

## Measured, with the project present

| Capability | Consumer's gate | 12.4.2 | Reading |
| --- | --- | --- | --- |
| LLM Mesh (`llms`) | 12.3.0 | **400** | Endpoint exists, wants a parameter |
| Knowledge Banks | 12.5.0 | **200** | **Route present**, below the gate |
| agents | — | 404 | Absent |
| semantic models | — | 404 | Absent |
| datasets *(control)* | — | 200 | Present, as expected |

LLM Mesh existing at 12.4.2 is exactly what a 12.3.0 gate predicts.

## The Knowledge Banks result needs its caveat stated first

The route is registered on 12.4.2, **below** the 12.5.0 gate. This is **not**
evidence the gate is wrong.

The consumer's gates are defined at the **MCP tool-exposure layer**, not on REST
routes — whether `list_knowledge_banks` and friends are available on a version.
A registered REST route is a different fact at a different layer, and the two can
legitimately disagree: the consumer's own LLM Mesh entry is annotated *"12.3.0,
pre-GA until 12.5.0"*, which is precisely a capability whose plumbing exists
before it is considered available.

So the honest statement is: **the knowledge-banks REST route is registered on
12.4.2.** Whether the capability is usable, and whether the MCP surface exposes
it, are separate questions this probe does not answer.

## Provenance

This instance was built with dependency checks skipped
(`deps_check: skipped`, see [SEEDING.md](../SEEDING.md)), because DSS 12.4.2's
installer rejects AlmaLinux 8.10.

For the rows above the caveat is weak: they are **route-registration** facts, and
a missing library does not unregister a route. It would matter for any claim that
a capability *works*.

DSS came up healthy regardless — `backend`, `ipython` and `nginx` all reached
supervisord `RUNNING`.
