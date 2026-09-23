#!/usr/bin/env python3
"""Seed a provisioned DSS instance with content shaped for upgrade assessment.

The consumer (the upgrade-planning skill) is strictly read-only, so all
content creation happens here. It asked for *shape, not scale*: roughly a dozen
projects chosen for coverage of specific DSS structures, not a large estate.

Seeding is deliberately per-era. Object types that do not exist on an older DSS
are simply absent there, and that sparseness is signal the consumer wants to
observe — not noise to be flattened. Do not "make the eras consistent".
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

OWNER = "admin"
MANAGED_CONNECTION = "filesystem_managed"


class DSS:
    """Thin DSS public-API client. Auth is HTTP basic: key as user, empty pass."""

    def __init__(self, url, api_key):
        self.url = url.rstrip("/")
        self.api_key = api_key

    def _req(self, method, path, body=None):
        req = urllib.request.Request(
            f"{self.url}/public/api{path}", method=method,
            data=None if body is None else json.dumps(body).encode(),
        )
        req.add_header("Content-Type", "application/json")
        import base64
        tok = base64.b64encode(f"{self.api_key}:".encode()).decode()
        req.add_header("Authorization", f"Basic {tok}")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read().decode()
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:400]
            raise RuntimeError(f"{method} {path} -> {e.code}: {detail}") from None

    # -- reads ---------------------------------------------------------------
    def version(self):
        return self._req("GET", "/admin/general-settings")  # cheap authenticated call

    def projects(self):
        return [p["projectKey"] for p in self._req("GET", "/projects/")]

    # -- writes --------------------------------------------------------------
    def create_project(self, key, name, description=""):
        if key in self.projects():
            return False
        self._req("POST", "/projects/", {
            "projectKey": key, "name": name, "owner": OWNER,
            "description": description, "permissions": [], "tags": ["dss-lab-seed"],
        })
        return True

    def datasets(self, pk):
        return [d["name"] for d in self._req("GET", f"/projects/{pk}/datasets/")]

    def create_managed_dataset(self, pk, name):
        """A managed filesystem dataset — no external dependency, works on every era."""
        if name in self.datasets(pk):
            return False
        self._req("POST", f"/projects/{pk}/datasets/", {
            "name": name, "projectKey": pk, "type": "Filesystem", "managed": True,
            "params": {
                "connection": MANAGED_CONNECTION,
                "path": f"{pk}/{name}",
                "notReadyIfEmpty": False,
            },
            "formatType": "csv",
            "formatParams": {"style": "excel", "separator": ",", "parseHeaderRow": True},
        })
        return True

    def set_schema(self, pk, name, columns):
        self._req("PUT", f"/projects/{pk}/datasets/{name}/schema",
                  {"columns": [{"name": c, "type": t} for c, t in columns]})

    def recipes(self, pk):
        return [r["name"] for r in self._req("GET", f"/projects/{pk}/recipes/")]

    def create_recipe(self, pk, proto, creation_settings=None):
        if proto["name"] in self.recipes(pk):
            return False
        proto["projectKey"] = pk
        self._req("POST", f"/projects/{pk}/recipes/", {
            "recipePrototype": proto,
            "creationSettings": creation_settings or {"rawCreation": True},
        })
        return True


    # -- slice 2 helpers -----------------------------------------------------
    def code_envs(self):
        try:
            return [e["envName"] for e in self._req("GET", "/admin/code-envs/")]
        except RuntimeError:
            return []

    def create_code_env(self, lang, name):
        if name in self.code_envs():
            return False
        self._req("POST", f"/admin/code-envs/{lang}/{name}?wait=true",
                  {"deploymentMode": "DESIGN_MANAGED"})
        return True

    def bind_project_code_env(self, pk, env_name):
        """Project level. The key here is `mode` — contrast set_recipe_env."""
        s = self._req("GET", f"/projects/{pk}/settings")
        py = s["settings"]["codeEnvs"]["python"]
        if py.get("mode") == "EXPLICIT_ENV" and py.get("envName") == env_name:
            return False
        py.update({"mode": "EXPLICIT_ENV", "envName": env_name, "preventOverride": False})
        self._req("PUT", f"/projects/{pk}/settings", s)
        return True

    def set_recipe_env(self, pk, recipe, env_mode, env_name=None):
        """Recipe level. The key here is `envMode`, NOT `mode`."""
        d = self._req("GET", f"/projects/{pk}/recipes/{recipe}")
        params = d["recipe"].get("params") or {}
        sel = {"envMode": env_mode}
        if env_name:
            sel["envName"] = env_name
        if params.get("envSelection") == sel:
            return False
        params["envSelection"] = sel
        d["recipe"]["params"] = params
        self._req("PUT", f"/projects/{pk}/recipes/{recipe}", d)
        return True


def ref(dataset, project=None):
    """DSS foreign-dataset convention: <projectKey>.<datasetName> across projects."""
    return f"{project}.{dataset}" if project else dataset


def io(items):
    return {"main": {"items": [{"ref": r} for r in items]}}


# ---------------------------------------------------------------------------
# Slice 1 — cross-project dataset reference
#
# The consumer's highest-value item: detect_cross_project_dependencies() and the
# scope rule that elevates a depended-on project to REVIEW have never run against
# a real node. This creates exactly that shape.
# ---------------------------------------------------------------------------

UPSTREAM = "SEED_SHARED_REF"
DOWNSTREAM = "SEED_CONSUMER"


def slice_cross_project(dss, log):
    created = []

    if dss.create_project(UPSTREAM, "Seed — shared upstream",
                          "Publishes a dataset consumed by another project."):
        created.append(f"project {UPSTREAM}")
    if dss.create_managed_dataset(UPSTREAM, "customers"):
        dss.set_schema(UPSTREAM, "customers",
                       [("customer_id", "bigint"), ("name", "string"),
                        ("signup_date", "date"), ("region", "string")])
        created.append(f"dataset {UPSTREAM}.customers")

    if dss.create_project(DOWNSTREAM, "Seed — cross-project consumer",
                          f"Consumes {UPSTREAM}.customers via the foreign-dataset convention."):
        created.append(f"project {DOWNSTREAM}")
    if dss.create_managed_dataset(DOWNSTREAM, "customers_local"):
        dss.set_schema(DOWNSTREAM, "customers_local",
                       [("customer_id", "bigint"), ("name", "string"),
                        ("signup_date", "date"), ("region", "string")])
        created.append(f"dataset {DOWNSTREAM}.customers_local")

    # The point of the slice: an input ref carrying another project's key.
    if dss.create_recipe(DOWNSTREAM, {
        "type": "sync",
        "name": "sync_customers_from_shared",
        "inputs": io([ref("customers", UPSTREAM)]),
        "outputs": io(["customers_local"]),
    }):
        created.append(f"recipe {DOWNSTREAM}.sync_customers_from_shared "
                       f"(input {UPSTREAM}.customers)")

    for c in created:
        log(f"  created {c}")
    if not created:
        log("  already present, nothing to do")
    return created


# ---------------------------------------------------------------------------
# Slice 2 — code envs bound at project AND recipe level
#
# The binding key is spelled differently at each level, which is real DSS
# behaviour rather than a misreading, and is a defect area for the consumer:
#
#   project level : settings.codeEnvs.python.mode        = EXPLICIT_ENV
#   recipe level  : params.envSelection.envMode          = EXPLICIT_ENV
#
# Both an EXPLICIT_ENV override and an INHERIT recipe are created, so the
# contrast between overridden and inherited is visible on one flow.
# ---------------------------------------------------------------------------

CODEENV_PROJECT = "SEED_CODEENV"
CODEENV_NAME = "seed_py_env"


def slice_code_envs(dss, log):
    created = []

    if dss.create_code_env("PYTHON", CODEENV_NAME):
        created.append(f"code env {CODEENV_NAME} (PYTHON, DESIGN_MANAGED)")

    if dss.create_project(CODEENV_PROJECT, "Seed — code env binding",
                          "Project- and recipe-level code env bindings."):
        created.append(f"project {CODEENV_PROJECT}")

    for ds in ("src", "out_explicit", "out_inherit"):
        if dss.create_managed_dataset(CODEENV_PROJECT, ds):
            dss.set_schema(CODEENV_PROJECT, ds, [("id", "bigint"), ("value", "string")])
            created.append(f"dataset {CODEENV_PROJECT}.{ds}")

    # project-level binding: key is "mode"
    if dss.bind_project_code_env(CODEENV_PROJECT, CODEENV_NAME):
        created.append(f"project-level binding EXPLICIT_ENV -> {CODEENV_NAME} (key: mode)")

    # recipe-level override: key is "envMode"
    for rname, out, env_mode in (
        ("compute_out_explicit_env", "out_explicit", "EXPLICIT_ENV"),
        ("compute_out_inherit_env", "out_inherit", "INHERIT"),
    ):
        if dss.create_recipe(CODEENV_PROJECT, {
            "type": "python", "name": rname,
            "inputs": io(["src"]), "outputs": io([out]),
        }, {"rawCreation": True, "payload": "# seeded by dss-lab\nimport dataiku\n"}):
            created.append(f"recipe {CODEENV_PROJECT}.{rname}")
        if dss.set_recipe_env(CODEENV_PROJECT, rname, env_mode,
                              CODEENV_NAME if env_mode == "EXPLICIT_ENV" else None):
            created.append(f"  recipe-level envMode={env_mode} on {rname}")

    for c in created:
        log(f"  created {c}")
    if not created:
        log("  already present, nothing to do")
    return created


# ---------------------------------------------------------------------------
# Slice 3 — non-canonical recipe types
#
# The consumer's recipe-type-to-language map misses these, and the Issue was
# stalled in "needs definition" because nobody had a confirmed live instance.
#
# `cpython` is delivered. A CustomCode_* recipe is NOT — see docs/SEEDING.md.
# ---------------------------------------------------------------------------

RECIPETYPE_PROJECT = "SEED_RECIPETYPES"


def slice_recipe_types(dss, log):
    created = []

    if dss.create_project(RECIPETYPE_PROJECT, "Seed — non-canonical recipe types",
                          "Recipe types the consumer's language map does not cover."):
        created.append(f"project {RECIPETYPE_PROJECT}")

    for ds in ("src", "out_cpython"):
        if dss.create_managed_dataset(RECIPETYPE_PROJECT, ds):
            dss.set_schema(RECIPETYPE_PROJECT, ds, [("id", "bigint"), ("value", "string")])
            created.append(f"dataset {RECIPETYPE_PROJECT}.{ds}")

    # cpython is a distinct recipe type from python and DSS accepts it directly
    if dss.create_recipe(RECIPETYPE_PROJECT, {
        "type": "cpython", "name": "compute_out_cpython",
        "inputs": io(["src"]), "outputs": io(["out_cpython"]),
    }, {"rawCreation": True, "payload": "# seeded cpython recipe\nimport dataiku\n"}):
        created.append(f"recipe {RECIPETYPE_PROJECT}.compute_out_cpython (type=cpython)")

    for c in created:
        log(f"  created {c}")
    if not created:
        log("  already present, nothing to do")
    return created


SLICES = {
    "cross-project": slice_cross_project,
    "code-envs": slice_code_envs,
    "recipe-types": slice_recipe_types,
}


def main():
    ap = argparse.ArgumentParser(description="Seed a DSS instance with assessment content")
    ap.add_argument("--url", required=True)
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--slice", default="cross-project", choices=sorted(SLICES))
    a = ap.parse_args()

    def log(m):
        print(m, file=sys.stderr)

    dss = DSS(a.url, a.api_key)
    log(f"seeding slice '{a.slice}' into {a.url}")
    created = SLICES[a.slice](dss, log)
    print(json.dumps({"slice": a.slice, "url": a.url, "created": created}, indent=2))


if __name__ == "__main__":
    main()
