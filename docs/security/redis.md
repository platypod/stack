# redis (security)

Authelia's session store.

- **Image:** `redis:7-alpine` (pinned).
- **Scope:** internal only (ClusterIP).
- **Role:** holds Authelia sessions so they survive an Authelia pod restart and can
  be shared across replicas.

Plain upstream Redis; no persistence tuning beyond defaults.
