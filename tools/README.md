# tools

Reusable research and diagnostic scripts. Standard library only. They are not
part of the `dss-lab` CLI and not exercised by `tests/run_tests.sh` beyond a
compile check.

| Script | Changes the node? | What it does |
| --- | --- | --- |
| `seed_zip_inspect.py <zip>...` | no | A DSS project export's source version, recipe and dataset types, connections, plugin recipes and cross-project refs |
