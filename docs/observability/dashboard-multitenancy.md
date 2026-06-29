# Per-user dashboard data isolation

**Status:** implemented & verified on **dev** (read-side scoping, Loki multitenancy,
and per-user ingest hardening). Not yet rolled to prod — see the prod caveats in the
migration + rollout notes below.

How we let several users share the Grafana dashboards (Claude usage, Jellyfin,
…) while each one sees **only their own data**, and admins see **everyone's**.
This is the decision record *and* the design; the short entries in
[../decisions.md](../decisions.md) and [../authentication.md](../authentication.md)
point here.

## The requirement

- Per-user signals (Claude Code usage, Jellyfin activity, future ones) become
  multi-user.
- A normal user opening a dashboard sees a view scoped to **themselves**.
- Members of the LLDAP **`admins`** group see **all** users, aggregated.
- It must generalise to *any* future signal we decide to isolate (metrics, logs),
  not be a one-off for one dashboard.

Grafana OSS has **no per-user datasource authorization** (label-based access
control / LBAC is an Enterprise feature). So isolation has to be enforced
*below* Grafana, at the datasource hop.

## The key insight: data shape decides the mechanism

There is no single "isolation tier". The right mechanism depends on **how the
data arrives**:

| Data shape | Example | Mechanism |
|---|---|---|
| **Per-authenticated stream** — each user's data arrives as a separately authenticated write | Claude transcripts (each laptop ships as its own LLDAP identity) | **Tenant** isolation (`X-Scope-OrgID`) — a hard, storage-layer wall |
| **Co-mingled at a shared source** — one writer emits everyone's data, distinguished by a label | Jellyfin (`one scrape, all users in the `user_name` label`); Claude metrics | **Label** isolation — a read-time enforced label matcher |

Multitenancy isolates at the **write-request boundary**, so it cannot split a
single co-mingled scrape (you'd need one pipeline per user). Co-mingled signals
*must* be label-isolated. Conversely, genuinely confidential per-stream content
(transcripts: real tool I/O, prompts, file contents) is worth a storage-layer
wall. So we use **each backend's natural primitive**.

## Decision

### Metrics (Mimir) → label isolation, stays single-tenant

- **`owner` is a universal label — every series carries one.** Personal metrics
  carry the user (Claude: stamped from identity; Jellyfin: `user_name` copied to
  `owner`); **all other (infra/shared) metrics are stamped `owner="_shared"`** in
  the collector. This is required because **prom-label-proxy rejects any regex
  that matches the empty string** (verified: `"regex should not match empty
  string"`) — so we can never rely on an unlabelled series passing through.
  Making `owner` universal means the matchers never need to match empty.
- A **`prom-label-proxy`** (`-regex-match`, `-header-name=X-Owner`,
  `-enable-label-apis`) fronts Mimir and injects `owner=~"<value>"` into every
  query and label/series request. The value comes from the shim via `X-Owner`:
  - normal user → `^(<user>|_shared)$` (own series + shared infra)
  - admin → `.+` (every owned series = everything)
  **No routing branch** — only the header value differs.
- Mimir keeps `multitenancy_enabled: false`; none of the historical-backfill
  limits (`out_of_order_time_window` etc., see [mimir.md](mimir.md)) change.

> **Migration caveat (real).** Once the metrics datasource is routed through the
> proxy, any series **already in Mimir without an `owner` label becomes invisible**
> (the matcher requires a non-empty owner, even for admins). New samples get
> `owner` after the collector change; pre-existing history (e.g. backfilled
> `ai_tx_*`) stays hidden until re-ingested/re-stamped. On dev this is moot;
> for prod, decide whether to re-ship history or accept the gap. **Order matters:**
> deploy the collector `owner` stamping *before* repointing the datasource.

### Logs (Loki) → multi-tenancy

Loki will hold **all k8s pod logs** *and* per-user Claude transcripts, and there
is **no mature OSS LogQL-rewriting proxy** (label-injection on Loki means
hand-merging matchers into an existing stream selector — fragile). So Loki uses
its native primitive:

| Data | Tenant | Readable by |
|---|---|---|
| Claude transcripts | `claude-<user>` (stamped at ingest from the authenticated identity) | that user + admins |
| All k8s pod logs | `platypod` (single) | admins only (non-admins are simply never scoped to it) |

- Enable `auth_enabled: true`. Keep the generous old-sample limits as **global
  defaults** so every per-user tenant inherits them.
- A normal user is scoped to their own `claude-<user>` tenant. An admin gets a
  **federated** read (`-querier.multi-tenant-queries-enabled`) over
  `platypod|claude-alice|claude-bob|…`.

### Enforcement: one datasource per backend + a "scope shim" reverse-proxy

> **Implementation note (deviation from the original plan).** The plan called for
> Traefik ForwardAuth. In practice that needs an *internal-only* Traefik entrypoint
> (a public IngressRoute trusting `X-Grafana-User` is forgeable, and the datasource
> hop carries no Authelia cookie). Rather than modify the core Traefik chart, the
> shim is instead a **ClusterIP reverse-proxy**: it makes the same scope decision,
> injects the headers itself, and forwards upstream. Self-contained in the
> observability module, never publicly exposed.

```
Grafana ─(send_user_header: X-Grafana-User  +  X-Shim-Auth: <secret>)─▶ SCOPE SHIM
                                                          (LLDAP group lookup; inject scope)
   Metrics datasource → shim → prom-label-proxy (-header-name=X-Owner -regex-match) → Mimir
   Logs   datasource → shim → Loki (X-Scope-OrgID injected)
```

- **Single datasource per backend.** Grafana sends `X-Grafana-User`
  (`[dataproxy] send_user_header = true`) and a shared-secret header; the datasource
  URL points at the shim, not the backend.
- **The scope shim** reads `X-Grafana-User`, looks the user's groups up in **LLDAP**
  (cached), injects the scope headers, and proxies the request upstream:
  - **Metrics:** `X-Owner: .+` if `admins ∈ groups`, else `X-Owner: ^(<user>|_shared)$`
    (own + shared infra — see the universal-`owner` note above). Consumed by
    prom-label-proxy.
  - **Logs:** `X-Scope-OrgID: claude-<user>`, or for an admin the federated list —
    **built dynamically by enumerating LLDAP users**, so even the admin tenant
    list is never hand-maintained.
- **Admin determination is live LLDAP `admins` membership** — no hardcoded admin
  list anywhere. Add someone to `admins`, they see everything; remove them, they're
  scoped. No redeploy.
- A separate shim instance per backend (different `UPSTREAM`): metrics →
  prom-label-proxy, logs → Loki.

This is why a small custom shim, not Authelia, owns this hop — see
*Rejected: approach A* below.

## What we are building

| Piece | Type | Notes |
|---|---|---|
| `grafana-authz` LLDAP account | config (seed) | member of **`lldap_strict_readonly`** (read-all, no write) |
| **Scope shim** | new Deployment + Service | ~50–100 lines (Go or Python); the only thing we write |
| `prom-label-proxy` | off-the-shelf image, Deployment + Service | `-regex-match`, `--header-name=X-Owner` |
| Traefik internal IngressRoutes + ForwardAuth middleware | config | one per backend |
| Grafana `send_user_header = true`; datasources → Traefik route | config | |
| Loki `auth_enabled: true` + per-user tenant stamping at ingest | config | global limits stay as defaults |
| Collector: stamp `owner` (Claude), relabel `user_name`→`owner` (Jellyfin), stamp Loki tenant from identity | config | |

## What we decided **not** to do, and why

- **Tier-1 "Viewer lockdown + `${__user.login}`".** Hardcode the user filter in
  the panel and rely on Viewers being unable to edit queries / reach Explore.
  *Rejected:* a soft boundary (breaks if anyone is ever an Editor; no protection
  on direct backend access) and doesn't generalise.

- **Full multi-tenancy for everything** (Claude metrics in per-user tenants too).
  *Rejected:* it fights the "admins see everything" requirement (needs tenant
  federation + a dynamic tenant list + `__tenant_id__`-aware aggregation),
  multiplies per-tenant backfill-limit management, and **structurally cannot do
  Jellyfin** (co-mingled at the scrape — see *data shape* above). Tenancy is the
  wrong tool for co-mingled signals.

- **Two datasources (a scoped one + an admin-bypass one).** *Rejected:* Grafana
  **OSS has no datasource-level permissions**, so "restrict the bypass datasource
  to admins" isn't actually enforceable — it leaks to any non-admin Editor. The
  single-datasource + shim design enforces server-side and is strictly stronger.

- **Approach A — forward the user's OAuth token (`oauthPassThru`) and re-auth at
  the proxy via Authelia.** *Rejected on feasibility.* Authelia **4.39.20**'s
  bearer-authz model requires a token granted the dedicated `authelia.bearer.authz`
  scope, with an explicitly-configured-and-requested **audience**, obtained via
  **PAR or client-credentials**. Grafana's `oauthPassThru` forwards its *interactive
  login* token — wrong audience (Grafana host), no bearer scope, wrong flow — so
  Authelia's Bearer endpoint rejects it. Making it work means bending the Grafana
  OIDC client into a bearer-authz client and adding refresh tokens (it has none
  today; default access-token lifespan ~1h ⇒ mid-session 401s). High fragility for
  no benefit over B.

- **Approach A′ — JWT access tokens + a Traefik JWT-validation plugin.** Dodges
  bearer-authz but adds a third-party Traefik plugin + per-client JWT-token config
  + refresh handling, to avoid one LLDAP call. *Rejected:* more moving parts than B.

- **Replacing Authelia** (Keycloak / Authentik / Zitadel) because of the above.
  *Rejected:* the shim is **inherent glue** for "Grafana OSS + per-user scoping" —
  you'd write the equivalent under any IdP, since mapping *user → datasource scope*
  is app-specific authorization no IdP does for you. Authelia is doing its real jobs
  (authn, OIDC, forward-auth) cheaply (32–64 Mi vs Keycloak's hundreds + a DB) and
  is deeply wired (≈8 OIDC clients, forward-auth, the OTLP basic-auth ingress).
  Swapping is a high-blast-radius migration for a benefit (clean token-exchange)
  that only matters to approach A, which we rejected anyway. **Revisit only if** a
  *different* pattern recurs: repeated fine-grained per-resource authz consumed by
  many backends (→ a policy engine like OpenFGA *alongside* Authelia), genuine
  service-to-service token exchange across many services (→ Keycloak/Zitadel), or
  outgrowing LLDAP's flat group model.

## Feasibility facts (audited)

- **Authelia 4.39.20** — bearer authz exists but is purpose-built for dedicated API
  clients (scope + audience + PAR), not for re-using a login token. (Basis for
  rejecting approach A.)
- **prom-label-proxy** — supports `-regex-match` and `--header-name`, so one
  instance serves both roles via the header value (`^user$` vs `.+`); no branch.
- **LLDAP** — `POST /auth/simple/login` `{username,password}` → `{token (1d),
  refreshToken (30d)}`; then `POST /api/graphql` `Bearer <token>` with
  `{ user(userId:"x"){ groups { displayName } } }`. **Caveat:** a regular account
  can only read *itself*; reading another user's groups needs a privileged account
  → the `lldap_strict_readonly` service account (verify on first deploy that the
  read-only role returns *other* users' groups; else fall back to `lldap_admin`).
  The shim must **cache** the LLDAP token + per-user group results (dashboards fan
  out many queries per refresh).
- Versions in play: Grafana OSS 13.0.2, Mimir 3.1.0, Loki 3.7.2, Traefik v3.7.5,
  LLDAP `stable`.

## Caveats & open items

- **`owner` ↔ Grafana-user alignment.** Enforcement compares `owner` to the
  authenticated username. Jellyfin users must be named after their Authelia names
  (or front Jellyfin with an OIDC plugin) for the match to land; otherwise a
  relabel/lookup is needed.
- **Trust boundary (important — CNI finding).** `X-Grafana-User` is only trustworthy
  if a rogue in-cluster pod can't hit the shim with a forged value. The plan relied
  on a NetworkPolicy locking the shim to Grafana — but **the cluster's CNI is flannel,
  which does not enforce NetworkPolicy** (Talos default). So the real control is a
  **shared secret**: Grafana attaches `X-Shim-Auth: <secret>` as a custom datasource
  header (`secureJsonData.httpHeaderValue1`) and the shim rejects any request without
  it. The NetworkPolicy is shipped as defense-in-depth (enforced only on a
  NetworkPolicy-capable CNI). The shim always *overwrites* client-supplied
  `X-Owner`/`X-Scope-OrgID`, so those can't be forged either.
- **Tempo / traces** are out of scope: OSS has no trace label-enforcement layer
  (TraceQL LBAC is Enterprise). Accepted.

## Implementation notes (as built on dev)

- **Loki tenant at ingest** — `ship-transcripts` sets `x-scope-orgid: claude-<owner>`
  on the OTLP **log** exporter (`--owner`, `$PLATYPOD_OWNER`, or the OS user). The
  gateway's `headers_setter` extension forwards it to Loki; a dedicated `batch/logs`
  processor (`metadata_keys: [x-scope-orgid]`) keeps tenants from mixing in a batch;
  the OTLP receiver needs `include_metadata: true`. Untagged logs → `_shared`.
- **Loki admin federation** — Loki runs with `-querier.multi-tenant-queries-enabled=true`
  so an admin's `X-Scope-OrgID: claude-a|claude-b|_shared` works.
- **Metric owner** — `ship-transcripts` stamps `owner` + a parallel `user` label on
  every `ai_tx_*` datapoint; the collector `transform/owner` defaults everything
  else to `owner=_shared` (Jellyfin → `user_name`).
- **Two shim instances** (`grafana-scope-shim`, `grafana-scope-shim-logs`) share one
  script ConfigMap, differ only in `UPSTREAM`.

## Migration of existing data

Once the datasources route through the proxies, **pre-existing data that lacks the
new labels/tenant is invisible** (and orphaned):

- **Metrics** — old `ai_tx_*` without `owner` are filtered out (not double-counted).
  Re-ship to restamp: `make ship-transcripts ARGS="--reset"` with `PLATYPOD_OWNER` set
  (per user). Infra metrics reflow with `owner=_shared` automatically within a scrape
  or two. Orphaned ownerless series age out (or delete via Mimir's delete API).
- **Logs** — transcripts ingested before `auth_enabled` live under the `fake` tenant;
  re-shipping sends them to `claude-<user>`. Orphaned `fake` data ages out (or delete
  via Loki's delete API / federate `fake` into the admin list temporarily).
- **Native Claude telemetry** (CLI, `service_name=claude-code-desktop`) lands in
  `_shared` unless the laptop's `~/.claude/settings.json` sets
  `OTEL_EXPORTER_OTLP_HEADERS` to include `x-scope-orgid=claude-<user>`.

## Ingest hardening: per-user write authorization (enforce-don't-stamp)

By default `--owner` is **client-declared** — a shipper could claim another user's
identity. For untrusted shippers, the ingest path enforces that a writer may only
write **its own** Loki tenant, without changing the client tool:

1. **Per-user gateway auth.** The OTLP/gRPC ingest rule is opened from the single
   `otel-telemetry` account to the **`otel-writers` group** (Authelia
   `access_control`, [authelia.yaml](../../values/default/security/authelia.yaml)).
   Each shipper authenticates with its **own** LLDAP creds, so Authelia's
   `Remote-User` is the real identity. `otel-telemetry` stays a group member (the
   shared/CI path) until every shipper is a real account.
2. **`tenant-guard` ForwardAuth shim** (`src/observability/.../tenant-guard/`),
   chained **after** `authelia-basic` on the gRPC ingress. It `403`s any request
   whose `x-scope-orgid` ≠ `claude-<slug(Remote-User)>`. Requests with no tenant
   header (metrics exports, native telemetry) are allowed — they claim no tenant
   and land in the default `_shared`.

**Coverage (important asymmetry):** this protects the **Loki tenant** (transcript
*content*) — a writer physically cannot write `claude-<someone-else>`. It does
**not** protect the **Mimir `owner` label**, which lives in the OTLP payload (not a
header) and stays client-declared — a writer could still mislabel its own *metrics'*
owner (fake token counts). Closing that would need payload-level stamping; left
open deliberately since the sensitive data is the content, not the counts.

Verified on dev: `otel-writers` member with matching `--owner` ships fine; the same
creds forging another `--owner` get `PERMISSION_DENIED` on the log export (metrics
still flow); a non-member is denied at Authelia.

### Why the guard (enforce), not the `headers_setter` stamp

Two ways to make the tenant trustworthy server-side. We **chose the guard** (the
client sets `x-scope-orgid`; the gateway 403s it if it isn't the writer's own
tenant). We **rejected the stamp** (repoint the gateway's existing `headers_setter`
at `Remote-User` so the tenant is *derived* server-side and the client's claim is
ignored entirely). Same security guarantee — no writing into another tenant — and
both are unbypassable (the middleware / exporter is mandatory on the path). It
came down to fit, not safety:

- **The stamp can't keep the `claude-` prefix.** `headers_setter` copies a context
  value *verbatim* (`from_context: remote-user` → tenant `dave`, not `claude-dave`);
  it has no templating. Using it would force **dropping the `claude-` prefix**,
  which ripples across the system: the read-side scope shim builds `claude-<user>`,
  prompt-meter's `tenant_prefix` is `claude-`, and all existing data lives under
  `claude-<user>` tenants (→ a re-ship). So "no new pod in the gateway" turns into a
  cross-cutting rename + data migration. Net: *less* tidy, not more — which corrects
  an earlier offhand "the stamp is tidier" remark.
- **The guard tightens the metric side too, for honest clients.** Passing the guard
  requires `x-scope-orgid == claude-<Remote-User>`, i.e. `--owner == Remote-User`;
  since prompt-meter uses the same `--owner` for the metric `owner` label *and* the
  tenant, an honest run that passes the guard also has a correct `owner` label. The
  stamp only fixes the tenant and leaves the metric label untouched.

**Accepted, still open:** a *custom malicious* tool could send metrics with a forged
`owner` and simply omit the tenant header (so the guard waves it through). Neither
approach closes that — it's a payload-level concern (see the *Coverage asymmetry*
above). Left open on purpose: the sensitive data is transcript *content* (the
tenant), not token *counts* (the label).

**Revisit the stamp only if** you decide to drop the `claude-` prefix for unrelated
reasons — then deriving the tenant from `Remote-User` becomes the natural, pod-free
choice.

## Rollout / testing note

Prefer to validate on the **dev** cluster first. Dev has had OIDC trouble in the
past (self-signed TLS on the OAuth back-channel — see the dev TLS/OIDC fix in the
prod values history); confirm Grafana OIDC login + `send_user_header` actually work
on dev before relying on it. If dev can't exercise the OIDC path, fall back to a
guarded test on **prd**.
