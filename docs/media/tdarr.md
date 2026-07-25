# tdarr (media)

Distributed transcoding/normalization pipeline for media libraries.

- **Images:** `ghcr.io/haveagitgat/tdarr:latest` (server) +
  `ghcr.io/haveagitgat/tdarr_node:latest` (in-cluster node).
- **Enabled:** disabled by default (`tdarr.enable=false`).
- **Auth:** Authelia `group:media`.
- **Storage:** media library on NFS `media`; Tdarr state/logs/cache on local
  `config` volume (SQLite/WAL-safe).
- **Runtime shape:** single Deployment with both server and node containers.
- **Setup automation:** [tdarr-setup](tdarr-setup-job.md) can bootstrap one
  value-driven flow + library (`tdarr.setup.*`) so you don't need manual UI
  setup for the baseline wiring.
