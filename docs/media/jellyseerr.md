# jellyseerr (media)

Request management front-end for Jellyfin + the *arr stack.

- **Image:** `ghcr.io/seerr-team/seerr:v3.3.0` (the maintained Seerr fork).
- **Database:** [postgres](postgres.md) (`postgres:17`).
- **Admin gotcha:** the admin role is **not** inherited from Jellyfin login — the
  [setup Job](jellyseerr-setup-job.md) writes the ADMIN bit directly into the DB.
  Watch for duplicate `pittinic` users (Jellyfin-linked vs local).
