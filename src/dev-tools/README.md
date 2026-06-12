# dev-tools module

Documentation, password management, database tooling and assorted dev utilities.
See [docs/services.md](../../docs/services.md) for the catalog.

## OIDC services

BookStack, Wiki.js, Outline and Vaultwarden all delegate login to Authelia via
OIDC. Clients are declared in the security module's Authelia ConfigMap; per-env
credentials live in `values/{dev,prd}/values.yaml`. See
[docs/authentication.md](../../docs/authentication.md).

- **Vaultwarden** uses the OIDC `code` flow with `offline_access` (SSO). The
  master-password vault is unchanged — OIDC governs *access* to the web vault.
- **Outline** has *no* local login path — OIDC is mandatory.
- **Wiki.js** version is pinned to whatever is currently running; check before
  bumping — downgrading the image downgrades its Postgres schema.

## CloudBeaver (dbeaver)

Pinned to **24.3.5** and intentionally **excluded from version bumps** — newer
releases have broken the saved-connection store in the past. Keeps its own admin
login (behind Authelia `group:dev`).

## Stateful backends

BookStack, Wiki.js and Outline each have their own DB (and Outline a Redis). The
`*-db` admin endpoints are exposed only to `group:dev`.

## whoami

Debug echo service (`group:dev`) — useful for verifying forward-auth headers and
routing without touching a real app.
