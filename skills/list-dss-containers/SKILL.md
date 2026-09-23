---
name: list-dss-containers
description: List local Dataiku DSS Docker containers with their versions, ports, URLs and running state. Use when the user asks what DSS instances or containers exist, which are running, what port or URL one is on, or which DSS versions are available locally (e.g. "what DSS instances do I have", "/list-dss-containers", "is DSS 12 running").
---

# List DSS containers

```bash
__DSS_LAB__ ls
```

Reports every dss-lab container — version, container name, state, port and URL —
read from Docker labels, so it reflects reality rather than a cached file.

Present it as a short table and lead with what the user actually asked. If they
wanted one instance's URL, `__DSS_LAB__ url <version>` prints just that.

For which versions are *available* rather than *present locally*, use
`__DSS_LAB__ catalog` (109 versions) or `__DSS_LAB__ catalog --all` for the full
table. `__DSS_LAB__ info <version>` shows everything derived from one version:
container name, volume, port, URL and whether it would be pulled or built.
