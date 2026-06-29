# Authentication

Every service is published through Traefik and protected by **Authelia**, which
plays two distinct roles in this stack:

1. **Forward-auth gateway** — a Traefik middleware (`forwardauth`) that sits in
   front of (almost) every IngressRoute. Authelia decides, per request, whether
   the caller is allowed through, based on the `access_control` rules in
   [`values/default/security/authelia.yaml`](../values/default/security/authelia.yaml).
2. **OIDC provider** — for apps that support OpenID Connect, Authelia is the
   identity provider. Those apps delegate *their own* login to Authelia instead
   of keeping a local password store. Clients are declared in
   [`src/security/templates/authelia/authelia--config-map.yaml`](../src/security/templates/authelia/authelia--config-map.yaml).

Users and groups live in **LLDAP** (`src/security`), which Authelia reads as its
backend. Group membership (`media`, `download`, `dev`) drives the access rules.

> **In-cluster OIDC discovery trick.** OIDC apps fetch the Authelia issuer
> metadata at its **public** HTTPS URL, which doesn't resolve inside the cluster.
> Each OIDC deployment therefore gets a `hostAliases` entry mapping
> `authelia.<domain>` → the Traefik LoadBalancer IP. See the Grafana / Komga /
> Kavita / RomM deployments for the pattern.

---

## 1. OIDC-integrated services

These delegate login to Authelia via OpenID Connect. No local passwords (beyond a
bootstrap admin). Each has an Authelia OIDC client registered.

| Service | Module | Notes |
|---------|--------|-------|
| Grafana | observability | OIDC via generic_oauth |
| BookStack | dev-tools | OIDC login |
| Wiki.js | dev-tools | OIDC strategy |
| Outline | dev-tools | OIDC is the only login method |
| Vaultwarden | dev-tools | SSO via OIDC (`response_types: [code]`, offline_access) |
| RomM | games | OIDC; account provisioning on first login |
| Reclaimerr | media | OIDC |
| Kavita | media | OIDC config pushed via settings API by the setup Job |
| ~~Komga~~ | media | **Disabled** (`enable: false`) — replaced by Kavita |

## 2. Services with their own user management

These keep their own user database / login screen. Authelia forward-auth still
gates the ingress (so an Authelia session is required to even reach them), and
they then apply a second, app-local login.

| Service | Module | Access rule |
|---------|--------|-------------|
| Jellyfin | media | bypass (own auth, public ingress) |
| Jellyseerr | media | bypass (own auth, public ingress) |
| Radarr / Sonarr / Readarr / Prowlarr / Bazarr | media | `group:media`; bypass from cluster CIDR for internal API calls |
| Mediarvester | media | `group:media` |
| Transmission / qBittorrent / Deluge | files | `group:download` |
| AdGuard Home | (network) | `group:dev` — own admin login |
| CloudBeaver (dbeaver) | dev-tools | `group:dev` — own admin login |
| Uptime-Kuma | observability | `group:dev` — own admin login |
| LLDAP | security | own admin UI |

## 3. Services with no auth of their own

These have no native authentication — they rely **entirely** on the Authelia
forward-auth layer (or are intentionally public).

| Service | Module | Access rule |
|---------|--------|-------------|
| Suwayomi | media | `group:media` (started with `AUTH_MODE=none`) |
| Dashy | core | `one_factor` |
| Homepage | core | `one_factor` |
| PokéClicker | games | `one_factor` |
| IT-Tools | dev-tools | bypass (public) |
| CyberChef | dev-tools | bypass (public) |
| whoami | dev-tools | `group:dev` (debug endpoint) |
| Flaresolverr | media | bypass from cluster CIDR only (internal) |
| Authelia / Traefik | security / core | bypass (Authelia is the auth portal itself) |

---

## Access groups (LLDAP)

| Group | Grants access to |
|-------|------------------|
| `media` | *arr stack, Mediarvester, RomM, Komga/Kavita, Suwayomi |
| `download` | Transmission, qBittorrent, Deluge |
| `dev` | AdGuard, BookStack, Wiki.js, Outline, CloudBeaver, Grafana, Loki/Mimir/Tempo, Uptime-Kuma, whoami, the `*-db` admin UIs |
| `otel-writers` | Push telemetry to the OTLP/gRPC gateway (Basic auth). The `tenant-guard` shim then limits each writer to its own `claude-<user>` Loki tenant — see [observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md). |

General-purpose pages (Dashy, Homepage, PokéClicker) only require any
authenticated user (`one_factor`), no specific group.

## Per-user dashboard data isolation (authorization)

Authelia/LLDAP handle *authn*; **data scoping** in the shared Grafana dashboards
(each user sees only their own Claude/Jellyfin data, `admins` see everyone) is a
separate *authorization* concern enforced below Grafana. It does **not** run
through Authelia on the datasource hop — a small ForwardAuth "scope shim" derives
admin-ness live from the LLDAP `admins` group instead (the bearer-authz path was
rejected on feasibility). The `admins` group therefore also governs dashboard
scope.

→ Full design + rationale: [observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md).

## Adding a new OIDC client

1. Add the client block to `authelia--config-map.yaml` (hash the secret with
   `authelia crypto hash generate pbkdf2 --variant sha512`).
2. Add per-env `oidc.clientId` / `clientSecret` to `values/dev/values.yaml` and
   `values/prd/values.yaml`.
3. Add `hostAliases` (Authelia public host → `traefik.loadBalancerIP`) to the
   app's Deployment, gated on `oidc.clientId`.
4. Configure the app to use `https://authelia.<domain>` as issuer.
