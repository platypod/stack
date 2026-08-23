# Authentication

Every service is published through Traefik and protected by **Authelia**, which
plays two distinct roles in this stack:

1. **Forward-auth gateway** — a Traefik middleware (`forwardauth`) that sits in
   front of (almost) every IngressRoute. Authelia decides, per request, whether
   the caller is allowed through, based on `access_control` rules. Most of these
   rules are **generated**, not hand-written — see "Access groups" below.
2. **OIDC provider** — for apps that support OpenID Connect, Authelia is the
   identity provider. Those apps delegate *their own* login to Authelia instead
   of keeping a local password store. Clients are declared in
   [`src/security/templates/authelia/authelia--config-map.yaml`](../src/security/templates/authelia/authelia--config-map.yaml).

Users and groups live in **LLDAP** (`src/security`), which Authelia reads as its
backend. Group membership drives the access rules — see "Access groups" below
for the current per-tool/per-role group model.

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
| Audiobookshelf | media | OIDC config pushed via `PATCH /api/auth-settings` by the setup Job (undocumented endpoint, found by reading the app's source) |
| ~~Komga~~ | media | **Disabled** (`enable: false`) — replaced by Kavita |

## 2. Services with their own user management

These keep their own user database / login screen. Authelia forward-auth still
gates the ingress (so an Authelia session is required to even reach them), and
they then apply a second, app-local login.

| Service | Module | Access rule |
|---------|--------|-------------|
| Jellyfin | media | bypass (own auth, public ingress) — local accounts, plus optional LLDAP-backed login via the LDAP-Auth plugin (`jellyfin_user`/`jellyfin_admin`/`media_user`/`media_admin`/`admins` to log in — admin-tier groups included so admin-only membership isn't locked out, confirmed by testing; `jellyfin_admin`/`media_admin`/`admins` additionally auto-promoted to Jellyfin admin); dev automated, prod manual — see [media/jellyfin-ldap.md](media/jellyfin-ldap.md) |
| Jellyseerr | media | bypass (own auth, public ingress) — has its own admin bit, but it's DB-written by username, not group-driven |
| Radarr / Sonarr / Readarr / Prowlarr / Bazarr | media | per-tool `<tool>_user` + `media_user`/`admin` + `admins`; bypass from cluster CIDR for internal API calls |
| Mediarvester | media | `mediarvester_user`; `mediarvester_admin`/`media_admin`/`admins` grants in-app admin (reads the forwarded LDAP-groups header directly — see `mediarvester/src/api/deps.py`) |
| Transmission / qBittorrent / Deluge | files | `<tool>_user` + `download_user` + `admins` |
| AdGuard Home | (network) | `adguard_user` + `dev_user`/`dev_admin` + `admins` — own admin login |
| CloudBeaver (dbeaver) | dev-tools | `dbeaver_user` + `dev_user`/`dev_admin` + `admins` — own admin login |
| Uptime-Kuma | observability | `uptimeKuma_user` + `dev_user`/`dev_admin` + `admins` — own admin login |
| LLDAP | security | own admin UI |

## 3. Services with no auth of their own

These have no native authentication — they rely **entirely** on the Authelia
forward-auth layer (or are intentionally public).

| Service | Module | Access rule |
|---------|--------|-------------|
| Suwayomi | media | `suwayomi_user` + `media_user`/`admin` + `admins` (started with `AUTH_MODE=none`, no user system at all) |
| Dashy | core | `one_factor` |
| Homepage | core | `one_factor` |
| PokéClicker | games | `one_factor` |
| IT-Tools | dev-tools | bypass (public) |
| CyberChef | dev-tools | bypass (public) |
| whoami | dev-tools | `whoami_user` + `dev_user`/`admin` + `admins` (debug endpoint) |
| Flaresolverr | media | bypass from cluster CIDR only (internal) |
| Authelia / Traefik | security / core | bypass (Authelia is the auth portal itself) |

---

## Access groups (LLDAP)

Groups are **generated**, not hand-maintained, from a single table:
[`values/default/security/access-groups.yaml`](../values/default/security/access-groups.yaml).
That file is the source of truth — see its header comment for the full field
reference. Two things read it:

- **LLDAP seed** (`security.allGroupNames` in
  [`src/security/templates/_helpers.tpl`](../src/security/templates/_helpers.tpl))
  — the full flattened group list the seed Job creates.
- **Authelia rules** (`security.toolSubjects` / `security.toolHosts`, same file)
  — one generated `access_control` rule per tool in
  [`authelia--config-map.yaml`](../src/security/templates/authelia/authelia--config-map.yaml).
  A handful of hand-written rules still live in
  [`values/default/security/authelia.yaml`](../values/default/security/authelia.yaml)
  for things the table doesn't cover (bypass-only tools, the cluster-CIDR
  bypass for the *arr internal API calls, the OTLP ingest rule).

**Two group tiers per tool, only where real:**

- `<tool>_user` — every tool gets one. Grants basic access.
- `<tool>_admin` — **only** for tools with an actual, currently-usable
  in-app admin mechanism: `jellyfin_admin` (LDAP-Auth plugin filter),
  `mediarvester_admin` (reads the forwarded LDAP-groups header directly),
  `grafana_admin` (dashboard scope-shim), `bookstack_admin` (OIDC-group-to-role
  sync). Every other tool has real in-app roles that *aren't* group-driven yet
  (Jellyseerr, Kavita, Audiobookshelf) or unverified ones (RomM, Wiki.js,
  Outline, CloudBeaver) — no group was created for those since nothing would
  consume it. See each entry's `evidence`/`verified` field in access-groups.yaml.

**Composite (category) groups**, LLDAP has no nested groups, so these are flat
sibling groups referenced alongside the granular ones, not true inheritance:

| Group | Grants access to |
|-------|------------------|
| `media_user` / `media_admin` | Every media-category tool's user tier / the tools with a real admin tier (Jellyfin, Mediarvester) |
| `download_user` | Transmission, qBittorrent, Deluge, SABnzbd — no `download_admin`, nothing in this category has an admin tier |
| `dev_user` / `dev_admin` | Every dev-category tool's user tier / the tools with a real admin tier (Grafana, BookStack) |
| `otel_writer` | Push telemetry to the OTLP/gRPC gateway (Basic auth). The `tenant-guard` shim then limits each writer to its own `claude-<user>` Loki tenant — see [observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md). Standalone — not part of any category. |
| `admins` | Global superuser — appended to every generated rule and app-side role check on top of whatever else is declared |

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
