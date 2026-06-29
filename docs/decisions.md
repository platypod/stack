# Stack decisions

Non-obvious *why-we-built-it-this-way* choices for the workload stack. Chart
structure and conventions live in [conventions.md](conventions.md); the
infra-layer equivalent is [../../infra/docs/decisions.md](../../infra/docs/decisions.md).

## Per-user dashboard data isolation (multi-user Grafana)

Several users share the Grafana dashboards but each sees only their own data;
LLDAP `admins` see everyone. Enforced **below Grafana** (OSS has no datasource
LBAC) using each backend's natural primitive — **label** isolation for Mimir
(`prom-label-proxy` enforcing an `owner` label, also covers Jellyfin), **tenant**
isolation for Loki (per-user `claude-<user>` tenants + a `platypod` tenant for
pod logs) — fronted by a tiny **ForwardAuth "scope shim"** that derives admin-ness
live from LLDAP (no hardcoded list).

Rejected: Viewer-lockdown (soft), full multitenancy (can't do co-mingled Jellyfin),
two-datasource admin bypass (no OSS datasource permissions), token-forward /
`oauthPassThru` (Authelia 4.39 bearer-authz won't accept a login token), and
swapping Authelia (the shim is inherent glue, not an Authelia shortcoming).

→ Full decision record + design: [observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md).
