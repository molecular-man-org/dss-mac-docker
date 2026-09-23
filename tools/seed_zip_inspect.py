#!/usr/bin/env python3
"""Summarise a DSS project export ZIP: source version, deps, recipe/dataset types.

Read-only; reads only metadata entries, never dataset contents.
Usage: tools/seed_zip_inspect.py <export.zip> [more.zip ...]
"""
import collections
import json
import sys
import zipfile


def read_json(z, name):
    try:
        return json.loads(z.read(name).decode("utf-8", "replace"))
    except Exception:
        return None


for path in sys.argv[1:]:
    z = zipfile.ZipFile(path)
    names = z.namelist()
    m = read_json(z, "export-manifest.json") or {}
    params = read_json(z, "project_config/params.json") or {}
    recipes, datasets, conns = collections.Counter(), collections.Counter(), collections.Counter()
    for n in names:
        if n.startswith("project_config/recipes/") and n.endswith(".json"):
            recipes[(read_json(z, n) or {}).get("type", "?")] += 1
        elif n.startswith("project_config/datasets/") and n.endswith(".json"):
            d = read_json(z, n) or {}
            datasets[d.get("type", "?")] += 1
            c = (d.get("params") or {}).get("connection")
            if c:
                conns[c] += 1
    print(f"== {path}")
    print(f"  project            : {m.get('originalProjectKey')}")
    print(f"  exported from DSS  : {m.get('generatedWithDSSVersion')}")
    print(f"  project status     : {params.get('projectStatus')!r}")
    print(f"  recipe types       : {dict(recipes.most_common())}")
    print(f"  plugin recipes     : {[t for t in recipes if t.startswith('CustomCode_')] or 'none'}")
    print(f"  dataset types      : {dict(datasets.most_common())}")
    print(f"  connections        : {dict(conns.most_common())}")
    print(f"  cross-project refs : {m.get('foreignObjects') or 'none'}")
    print(f"  allowed-missing    : conns={m.get('allowedMissingConnections')} envs={m.get('allowedMissingCodeEnvs')}")
    print("  note: exportedWithPlugins lists every plugin on the SOURCE instance, not project usage")
