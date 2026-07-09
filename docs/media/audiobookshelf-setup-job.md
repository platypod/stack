# audiobookshelf-setup (Job)

Post-install/post-upgrade hook that creates Audiobookshelf's root user and
pushes its Authelia OIDC config — fully unattended, no browser wizard.

- **Template:** `src/media/templates/audiobookshelf/audiobookshelf--setup-job.yaml`
- Audiobookshelf's root user is fixed at first-init (`POST /init`), unlike
  Kavita's "first registered user is admin".
- OIDC is pushed via `PATCH /api/auth-settings`, an endpoint with no public
  docs — found by reading the app's own source in-cluster.
- **No DB shortcut**: unlike Jellyseerr's admin-bit job, this can't write
  Audiobookshelf's SQLite directly — `Database.userModel` caches users in
  memory after first lookup, so a row updated out-of-band is invisible to the
  running process until it restarts. Everything goes through the live HTTP API
  instead.
- `audiobookshelf.credentials` (default values) must keep matching the root
  user's actual password — if that password is ever reset out-of-band, the
  live process needs a restart before the new value is visible (same caching
  caveat as above).

See [audiobookshelf](audiobookshelf.md).
