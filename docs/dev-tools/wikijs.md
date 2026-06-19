# wikijs (dev-tools)

Wiki.js — wiki platform.

- **Image:** `ghcr.io/requarks/wiki:2.5.314` (pinned, 2.x line).
- **Database:** [postgres](postgres.md) (`postgres:17`).
- **OIDC:** [wikijs-oidc-seed-job](wikijs-oidc-seed-job.md) configures the Authelia
  OIDC strategy (Wiki.js stores auth strategies in its DB, so they're seeded).
- **Exposure:** host via Traefik.
