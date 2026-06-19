# postgres (dev-tools)

Shared-image Postgres used by the dev-tools apps that need it — **separate instances**
per app (Wiki.js, Outline), never shared.

- **Image:** `postgres:17` (pinned).
- **Scope:** internal only (ClusterIP); no ingress.

Stock Postgres; credentials from each app's values.
