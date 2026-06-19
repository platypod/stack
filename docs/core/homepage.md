# homepage (core)

gethomepage/homepage — the landing dashboard at the apex domain
(`homepage.<domain>`), linking out to every service with status widgets.

- **Image:** `homepage.image` (pinned).
- **Port:** `3000`.
- **Config:** services/groups/widgets are rendered from a ConfigMap
  (`homepage--config-map.yaml`); the pod carries a `checksum/config` annotation so
  it restarts when that config changes.

Mostly default upstream behaviour — the substance is the service catalog in the
ConfigMap. Note: widget API keys (e.g. for the *arr apps) reference the same secrets
the apps use; keep them in sync when rotating.
