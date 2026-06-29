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

## Per-user telemetry ingest hardening (enforce, don't stamp)

`--owner` is client-declared, so a shipper could claim another user's identity. The
ingest path now authorizes per-user writes: the OTLP/gRPC Authelia rule is opened to
the **`otel-writers`** group (each shipper uses its own LLDAP creds → real
`Remote-User`), and a **`tenant-guard` ForwardAuth shim** (after `authelia-basic`)
**403s** any request whose `x-scope-orgid` ≠ `claude-<Remote-User>`. So a writer can
only write its own Loki tenant. Tenant-less traffic (metrics, native telemetry) is
allowed → `_shared`. `otel-telemetry` stays a group member (shared/CI path) until
all shippers are real accounts.

Chosen the **guard (enforce/403)** over the **`headers_setter` stamp** (derive the
tenant from `Remote-User`, ignore the client): the stamp copies the username
verbatim so it can't keep the `claude-` prefix → would force a system-wide prefix
rename + re-ship. Guard also tightens the metric `owner` for honest clients.
**Open gap:** the Mimir `owner` label is in the OTLP payload, so neither approach
stops a custom tool forging metric owner (low-sensitivity — counts, not content).

→ Detail in the *Ingest hardening* section of [observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md).
