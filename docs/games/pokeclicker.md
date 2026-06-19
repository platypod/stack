# pokeclicker (games)

Self-hosted PokéClicker.

- **Image:** `ghcr.io/platypod/pokeclicker:v0.10.25` — **custom image** built to GHCR
  (source in `pokeclicker/` at the repo root), pinned.
- **Port:** `3000`. Host via Traefik, behind Authelia `one_factor`.
- Static web app; no persistent storage.

Rebuild/push with `make build IMAGE=pokeclicker VERSION=vX.Y.Z`.
