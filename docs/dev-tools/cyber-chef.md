# cyber-chef (dev-tools)

CyberChef — "the cyber Swiss-army knife" (encoding/encryption/data-analysis recipes).

- **Image:** `ghcr.io/platypod/cyber-chef:v11.0.0` — **custom** image built to GHCR
  from `cyber-chef/` at the repo root, pinned.
- **Exposure:** host via Traefik, behind Authelia.
- Static web app; no persistent storage.

Rebuild/push with `make build IMAGE=cyber-chef VERSION=vX.Y.Z`.
