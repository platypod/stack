# komga-setup (Job)

Post-install/upgrade hook that claims the Komga admin (if unclaimed) and
creates any library declared in `komga.libraries` that doesn't already exist.

- **Template:** `src/media/templates/komga/komga--setup-job.yaml`
- Idempotent: never touches a library that already exists — manual tweaks
  made from the admin UI afterward are left alone.
- Gated on `komga.credentials.email`/`password` being set — if Komga was
  claimed by hand before this Job existed, these must match the real admin
  login, or every call 401s (the Job logs a warning and exits 0 rather than
  crash-looping).

See [komga](komga.md).
