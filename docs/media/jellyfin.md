# jellyfin (media)

The media server.

- **Image:** `jellyfin.image` (pinned, e.g. `10.11.11`).
- **Storage:** library read-only on NFS `media` (`jellyfin.pvc.media`, mounted
  at `/media`); config on `jellyfin.pvc.config`.
- **Metrics:** scraped via the json-exporter `jellyfin` module (playback) and/or the
  native Prometheus endpoint — both optional, gated in the collector values.
- **Setup:** [jellyfin-setup](jellyfin-setup-job.md) seeds initial config.
- **LDAP auth + Moonfin plugin + library seeding:** see
  [jellyfin-ldap.md](jellyfin-ldap.md) — automated in dev, manual on prod
  (host-native, outside this repo).
