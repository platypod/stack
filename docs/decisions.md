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
the **`otel_writer`** group (each shipper uses its own LLDAP creds → real
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

## Git → Outline docs mirror: one-way, pull-based, read-only

Outline is the collaboration/intel surface; the git repos hold the engineering
docs. They're linked by the **`outline-sync` CronJob** (dev-tools): nightly, it
clones the configured public repos and pushes their markdown into one
**read-only collection per repo** via Outline's API (internal Service, token
from values — nothing leaves the cluster). Git stays the only source of truth
for mirrored docs; **content authored in Outline stays in Outline** and is
never synced back to git (explicitly decided — "what happens on Outline stays
on Outline").

Rejected: **two-way sync** (Outline stores ProseMirror, markdown round-trips
aren't byte-stable → phantom diffs and a hand-rolled merge engine; community
2-way tools exist but inherit the same lossiness), **GitHub-Actions push**
(e.g. `outline-sync-action` — parks an Outline API token on third-party
infrastructure, same posture violation the org rejects for deploy
credentials, and would have to thread past the ingress from outside),
**Wiki.js native git storage** (real built-in two-way git sync, but the
collaboration/editing experience loses to Outline and collaboration is the
point), and **an Outline→git export/backup flow** (declined for now with the
one-way rule; revisit only if Outline-native content ever needs history
outside Outline's own).

Upstream git sync remains an open discussion
([outline#9952](https://github.com/outline/outline/discussions/9952)) — if it
ever lands first-party, revisit the custom job. Details and token setup:
[dev-tools/outline.md](dev-tools/outline.md).

## Docmost not deployed (no free OIDC)

Considered Docmost as a 4th wiki/docs app to compare against Outline, BookStack, and
Wiki.js (dev-tools). **Not deployed** — every other dev-tools wiki gets Authelia OIDC;
Docmost can't, so it wouldn't fit the module's pattern.

Docmost's self-hosted OSS edition has no OIDC/SAML/LDAP at all — SSO lives entirely in
their closed-source `ee/` submodule, gated behind the paid Business plan
($3.50/seat/mo). A maintainer closed the one community PR that tried to add free OIDC
([docmost/docmost#1740](https://github.com/docmost/docmost/pull/1740)) with "SSO is
already available in the Docmost enterprise edition." The only known workaround is
patching the compiled license-decryption code to fake an Enterprise license — a
licensing crack, not a config trick.

Rejected: deploying with local login behind Authelia forward-auth only (breaks the
"every dev-tool here is OIDC'd" consistency for no clear benefit), the license-patch
workaround (circumvents paid licensing, out of bounds regardless of context), buying
the Business license (real option if this gets revisited, just not taken now).

If revisited: re-check whether OIDC has been open-sourced upstream before assuming
this is still accurate.
