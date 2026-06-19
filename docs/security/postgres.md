# postgres (security)

Backing database — **two separate instances** in this module, one per consumer:
`authelia-db` and `lldap-db`. (Other modules ship their own Postgres; this doc
covers the security ones.)

- **Image:** `postgres:17` (pinned).
- **Scope:** internal only (ClusterIP); no ingress.
- **Storage:** PVC per instance.
- **Credentials:** from each consumer's `database`/`credentials` values.

Plain upstream Postgres — nothing custom beyond the pin and per-instance isolation
(Authelia and LLDAP never share a DB).
