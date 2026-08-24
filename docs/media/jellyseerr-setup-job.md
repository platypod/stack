# jellyseerr-setup (Job)

Post-install hook that grants the admin role by **writing the ADMIN bit directly into
the Jellyseerr DB** — the role isn't inherited from a Jellyfin login.

- **Template:** `src/media/templates/jellyseerr/jellyseerr--setup-job.yaml`
- Watch for **duplicate `pittinic` users** (Jellyfin-linked vs local).

See [jellyseerr](jellyseerr.md).
