# wikijs-oidc-seed (Job)

Post-install hook that configures Wiki.js's **Authelia OIDC** authentication strategy
— Wiki.js stores auth strategies in its database, so they must be seeded rather than
set by env/config.

- **Template:** `src/dev-tools/templates/wikijs/wikijs--oidc-seed-job.yaml`
- Idempotent.

See [wikijs](wikijs.md).
