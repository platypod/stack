# jellyfin-setup (Job)

Post-install hook that seeds Jellyfin's initial configuration (skips the startup
wizard / sets up the admin + libraries).

- **Template:** `src/media/templates/jellyfin/jellyfin--setup-job.yaml`
- Idempotent; safe to re-run.

See [jellyfin](jellyfin.md).
