# audiobookshelf (media)

Audiobook/podcast server.

- **Image:** `ghcr.io/advplyr/audiobookshelf:2.35.1` (pinned).
- **Auth:** on the Authelia `group:media` access rule (own login) + optional OIDC.
- **Storage:** SQLite DB on the **local `config` volume** — same constraint as
  Kavita/Komga ([[sqlite-on-nfs-localconfig]]); `/metadata` (covers, backups,
  logs) is also on the local volume. The whole NFS media share is mounted at
  `/data` — add a library in the UI pointing at a sub-folder (e.g.
  `/data/audiobooks`), same minimal-config pattern as Kavita.
- **First boot:** no admin API/env (unlike Kavita) — complete the one-time setup
  wizard in the browser to create the initial admin account.
- **OIDC:** finished by hand in Settings -> Authentication (Issuer/Client
  ID/Secret) once `audiobookshelf.oidc.clientId` is set per-env — Audiobookshelf
  has no documented non-interactive settings API, so (unlike Kavita) no setup Job
  pushes this automatically. Requires PKCE (`S256`); redirect URIs are
  `/auth/openid/callback` (web) and `/auth/openid/mobile-redirect` (mobile app).
- **Setup:** none (no hook Job).
