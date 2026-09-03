---
name: stop-dss-container
description: Stop a running local Dataiku DSS Docker container by version. Use when the user asks to stop, halt, shut down or pause a DSS instance or container (e.g. "stop DSS 12.6.4", "/stop-dss-container 14.4.1", "shut down the 13 instance").
---

# Stop a DSS container

```bash
__DSS_LAB__ stop <version>
```

Accepts the same fuzzy version forms as starting one (`12.3`, `14`, `latest`).
Run `__DSS_LAB__ ls` first if you are unsure which instances exist.

Stopping preserves the datadir — restarting is fast because the DSS install and
first-boot work are already done. To delete the data as well, that is
`__DSS_LAB__ rm <version>`, which is destructive: confirm with the user first,
and mention `--keep-volume` as the non-destructive alternative.
