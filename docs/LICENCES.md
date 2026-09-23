# Licences

DSS will not run unlicensed, and no licence is distributed with this repo. Put
your licence files in **`~/.dataiku/licenses/`** — outside the repo, so none can
be committed by accident. `DSS_LAB_LICENSE_DIR` points elsewhere if you must.

## Core rule

Use the licence type that matches both the **instance's DSS version** and its
**commercial-package era**. For a standard end user who needs the broadest
product access, assign the highest **productive designer** profile — not an
administrative or technical-account profile.

| Licence type | Package era | DSS version guidance | Profiles | Maximum productive profile |
| --- | --- | --- | --- | --- |
| **2025** | FY2025 packages | **Requires DSS 12.6.0 or later.** New instances, or instances upgraded to 12.6.0+ | `DATA_DESIGNER`, `ADVANCED_ANALYTICS_DESIGNER`, `FULL_DESIGNER` | **`FULL_DESIGNER`** |
| **2024** | FY2021–FY2024 packages | The prior package model, including instances not eligible for 2025 | `VISUAL_DESIGNER`, `DESIGNER`, `EXPLORER`, `READER` | **`DESIGNER`** |
| **2018** | Legacy / internal-licence model | Old instances that still use legacy profiles and should not be migrated | `DATA_ANALYST`, `DATA_SCIENTIST` | **`DATA_SCIENTIST`** |

The 2025 tier is really three files, one per FY2025 package: `*-2025-enterprise`,
`*-2025-aiml` and `*-2025-analytics`.

```text
Licence type 2025 -> FULL_DESIGNER
Licence type 2024 -> DESIGNER
Licence type 2018 -> DATA_SCIENTIST
```

## 2025

The FY2025 licence and profile model, for newer DSS.

- **Will not work on DSS earlier than 12.6.0.** Use it only on 12.6.0 and later;
  it is the preferred choice for new instances. `provision` skips it below 12.6.0.
- `DATA_DESIGNER` — data-preparation and data-workflow access.
- `ADVANCED_ANALYTICS_DESIGNER` — analytics and ML oriented designer access.
- `FULL_DESIGNER` — the broadest standard end-user access. Assign this for
  maximum normal productive access.

## 2024

The profile model of the FY2021 through FY2024 packages.

- `READER` — consumption, read-only oriented.
- `EXPLORER` — limited, exploration oriented.
- `VISUAL_DESIGNER` — visual and low-code designer access.
- `DESIGNER` — the broadest standard creator access in this model, and the
  closest equivalent to modern `FULL_DESIGNER`. Assign this for maximum normal
  productive access.

It is the default choice here: accepted by every DSS era this repo has tested,
11.x through 15.x.

## 2018

The legacy model, primarily old internal licences.

- Use it only when the instance has an old internal or legacy licence **and** you
  do not want to migrate its user profiles.
- `DATA_ANALYST` — legacy analyst profile.
- `DATA_SCIENTIST` — legacy highest-access productive profile.

Equivalence across models: `DATA_SCIENTIST` ≈ `DESIGNER` ≈ `FULL_DESIGNER`, and
`DATA_ANALYST` ≈ `VISUAL_DESIGNER`.

## What "maximum access" means

Maximum **standard productive DSS access for a human user**. It does not mean
administrative privileges. Do not substitute `PLATFORM_ADMIN`, `ADMIN` or
`TECHNICAL_ACCOUNT` merely to maximise feature access: those are administrative
or service identities, not the normal full-feature creator entitlement, and are
assigned separately and only when the user actually administers the platform.

## Selection logic

```text
If DSS >= 12.6.0 and using FY2025 packaging:
    licence type 2025, maximum productive profile = FULL_DESIGNER
Else if using FY2021-FY2024 packaging:
    licence type 2024, maximum productive profile = DESIGNER
Else if the instance still uses legacy profile names and will not be migrated:
    licence type 2018, maximum productive profile = DATA_SCIENTIST
```

## How `provision` chooses

It walks the files in this order and applies the first one DSS accepts:

| Order | Glob | DSS versions |
| --- | --- | --- |
| 1 | `dev-*-2024.json` | all |
| 2 | `dev-*-2025-enterprise.json` | 12.6.0 and later |
| 3 | `dev-*-2025-aiml.json` | 12.6.0 and later |
| 4 | `dev-*-2025-analytics.json` | 12.6.0 and later |
| 5 | `dev-*-2018.json` | all |

Expired files are skipped with a warning. `--license FILE` overrides the order;
a 2025 licence given explicitly on a DSS older than 12.6.0 is still attempted,
with a warning. The globs follow one licence set's naming; edit
`LICENSE_GLOBS` in `bin/lib/provision.sh` to match yours.
