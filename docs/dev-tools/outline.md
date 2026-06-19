# outline (dev-tools)

Outline — team knowledge base / wiki.

- **Image:** `outlinewiki/outline:latest` (**unpinned**).
- **Backing stores:** **both** [postgres](postgres.md) (`postgres:17`) and
  [redis](redis.md) (`redis:7-alpine`) — Outline needs both.
- **Auth:** Authelia OIDC (`utilsSecret`/`clientSecret` in values).
- **Exposure:** host via Traefik.
