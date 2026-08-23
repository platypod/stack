# audiobookshelf (media)

Audiobook/podcast server.

- **Image:** `ghcr.io/advplyr/audiobookshelf:2.35.1` (pinned).
- **Auth:** on the Authelia `group:media` access rule (own login) + optional OIDC.
- **Storage:** SQLite DB on the **local `config` volume** — same constraint as
  Kavita/Komga ([[sqlite-on-nfs-localconfig]]); `/metadata` (covers, backups,
  logs) is also on the local volume. The whole NFS media share is mounted at
  `/data` — add a library in the UI pointing at a sub-folder (e.g.
  `/data/audio-books`), same minimal-config pattern as Kavita.
- **First boot:** root user created by the [audiobookshelf-setup](audiobookshelf-setup-job.md)
  Job via `POST /init` — no manual setup wizard needed.
- **OIDC:** pushed by the same setup Job via `PATCH /api/auth-settings`, once
  `audiobookshelf.oidc.clientId` is set per-env. That endpoint isn't publicly
  documented — reverse-engineered from the app's own source
  (`server/controllers/MiscController.js`) in-cluster. Requires PKCE (`S256`);
  redirect URIs are `/auth/openid/callback` (web) and `/auth/openid/mobile-redirect`
  (mobile app).
- **Setup:** [audiobookshelf-setup](audiobookshelf-setup-job.md).
