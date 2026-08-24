# authelia (security)

The auth gateway. Traefik forward-auths every protected route to it; it also acts
as an **OIDC provider** for apps that speak OIDC. Users come from [lldap](lldap.md).

- **Image:** `authelia/authelia:4.39.20` (pinned).
- **Storage:** Postgres (`postgres:17`, `authelia-db`). **Sessions:** `redis:7-alpine`.
- **Config:** `authelia--config-map.yaml` (pod has `checksum/config` to restart on change).
- **Secrets:** `secrets.{encryptionKey,jwt,session}`, `oidc.hmac_secret` — placeholders
  in default values, real ones per env.

## Auth surfaces (three endpoints)
- **`forward-auth`** (default) — browser, cookie/redirect. Every protected service
  uses the `authelia` Traefik middleware.
- **`forward-auth-basic`** — adds `HeaderAuthorization` so **`Authorization: Basic`**
  works (for non-interactive clients). Its own `authelia-basic` middleware. Used by
  the Claude Code OTLP telemetry path. See [decisions.md](../decisions.md).
- **OIDC** (`generic_oauth`) — for apps that authenticate via OIDC (Grafana, Kavita,
  RomM, Vaultwarden, etc.); clients declared under `oidc.clients`.

## access_control policies (non-default, worth knowing)
- Default **`one_factor`** for browser services (homepage, pokeclicker, grafana…).
- **`bypass`** for the **\*arr local APIs** (radarr/sonarr/prowlarr/readarr/bazarr/
  flaresolverr/reclaimerr) and **Kavita** — these expose their own auth or are
  API-consumed, so forward-auth would break them.
- Prod adds the `user:otel-telemetry` Basic rule on the gRPC OTLP host.

## Gotchas
- Grafana OIDC back-channel needs the Authelia hostname resolvable in-cluster →
  a `hostAlias` to the Traefik LB IP (see grafana deployment).
- Bearer-token authz is available on 4.39 but the OTEL path uses Basic (static header,
  no 1h expiry). See [decisions.md](../decisions.md).
