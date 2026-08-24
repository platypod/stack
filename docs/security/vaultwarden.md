# vaultwarden (security)

Bitwarden-compatible password manager server.

- **Image:** `vaultwarden/server:1.36.0` (pinned).
- **Auth:** integrates Authelia **OIDC** (part of the OIDC-expansion set).
- **Storage:** SQLite on the **local `config` volume** (WAL — not NFS; see
  [conventions.md](../conventions.md)).
- **Exposure:** host via Traefik (TLS). Vaultwarden requires HTTPS for the web vault
  and WebSocket notifications.
