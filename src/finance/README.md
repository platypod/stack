# finance module

Personal-finance data platform, **phase 0**: a dedicated PostgreSQL plus the CronJobs
that run the `finance-pipelines` image. Design and phases:
[`docs/plans/finance-data-platform.md`](../../../docs/plans/finance-data-platform.md);
code, contracts and dbt project: [`finance-pipelines/`](../../../finance-pipelines/README.md).

**Disabled by default** (`finance.enable: false` renders nothing). See
[Enabling](#enabling) first.

## What it deploys

| Resource | Purpose |
|---|---|
| `finance-db` (Deployment, Service, ConfigMap) | `postgres:17`, database `finance`, roles `finance_{ingest,transform,grafana}` created once on first init. Dedicated: *not* `transverse-db` (media's shared instance, on the NFS-backed `apps` volume) and not the auth DBs. |
| `finance-pipeline-env` (Secret) | `FINANCE_PG_*` per-role credentials, OTLP endpoint (observability gateway), OpenLineage settings. |
| `finance-migrate` (post-install/upgrade hook Job) | `pp migrate`: schemas, grants, `ops` tables and contract-generated DDL. Idempotent. |
| `finance-payslips` (CronJob, weekly, **off by default**) + read-only NFS PV/PVC `finance-payslips` | Payslip pipeline on the NAS home share (`finance.pipelines.payslips`). Image carries tesseract/poppler for the scanned months. |
| `finance-grafana` (Deployment, Service, IngressRoute, ConfigMaps, Secret; **off by default**) | Optional dedicated Grafana with a Postgres datasource. See *Access model*, last section. |
| `finance-db-dump` (CronJob, nightly) | Logical `pg_dump -Fc` to the NFS `apps` share, verified with `pg_restore --list`, 14-day retention. See *Backups*. |
| `finance-heartbeat` (CronJob, daily) | Canary pipeline: ingest → dbt → contract tests, with traces/metrics/logs and OpenLineage events. |

Telemetry goes to the observability OTel gateway (Tempo/Mimir/Loki). OpenLineage
events are stored in `ops.openlineage_event` (no backend yet).

## Enabling

1. **Publish the image** `ghcr.io/platypod/finance-pipelines:<tag>` (built from
   `finance-pipelines/`) and set `finance.image`.
2. **Credentials**: set the four `finance.database.credentials.*.password` in
   `platypod-sops` (`clusters/<env>/secrets.enc.yaml`). A placeholder fails the render.
3. **prod only — database volume**: declare a local, node-pinned volume in
   `storage.localDb.volumes` (e.g. `- {name: finance-db, node: <hostname>}`, enable
   `storage.localDb`) and set `finance.database.storage.pvc: finance-db`. The default
   (`apps`) is NFS on prod: unsafe for Postgres and unsnapshotted.
4. Set `finance.enable: true` for the environment.
5. Shared Grafana (recommended): see *Access model* (`finance.publish.*`).
   Dedicated Grafana (optional): set `finance.grafana.enable: true` and the OIDC client
   (`finance.grafana.oidc.clientId` / `clientSecret.plain` / `clientSecret.hashed`) in platypod-sops,
   generate the hash with the `docker run … authelia crypto hash generate pbkdf2` command shown in
   `apps/base/values/finance.yaml`, and make sure your LLDAP user is in `admins` (or `finance_user`).
   Authelia registers the client only when `clientId` is set; the chart refuses to render without it.
6. Payslips: set `finance.pipelines.payslips.enable: true` and check `…payslips.nfs.share` (the
   default points at `/volume1/homes/pittinic/bulletins-de-salaire`) and the NFS `server`.

## Pitfalls

- **Roles are created only on first init** of an empty data dir. Changing a password
  later needs `ALTER ROLE` by hand (like LLDAP).
- **Never set `fsGroup`** on the DB pod (NFS recursive chown rule).
- **`localDb` backups are a `tar` of the live data dir** (see
  `persistence/templates/local-db/backup-cronjob.yaml`): inconsistent-at-worst for a running
  Postgres. That is why `finance-db-dump` exists; restore from the dump (see *Backups*).
- The migrate hook only creates; it does not alter existing tables when a contract
  changes (phase-0 limitation).

## Access model (revised 2026-10-03: shared Grafana, per-user isolation)

**Decision: payslips are shown in the *shared* Grafana, isolated per user by the same mechanism
Jellyfin uses** (`docs/observability/dashboard-multitenancy.md`): data carries an `owner` label,
the scope shim injects the caller's own `owner` matcher into every query, `prom-label-proxy`
enforces it. This supersedes the 2026-10-02 decision (a dedicated Grafana); that chart stays as
an optional, off-by-default alternative (`finance.grafana.*`, Postgres datasource, Postgres
dashboard) for ad-hoc SQL.

```
Postgres gold ──pp run payslips──▶ finance.* gauges (owner=<login>, historical timestamps)
   ──▶ OTel gateway (pipeline metrics/otlp_finance: only finance.*, drops series without a real owner)
   ──▶ Mimir tenant `finance` (own retention/limits) ──▶ prom-label-proxy ◀── scope shim ◀── Grafana "Mimir (finance)"
```

What a user sees: `X-Owner` = `^(<login>|_shared)$` for non-admins, `.+` for members of `admins`.
So **pittinic sees pittinic's payslips, a non-admin (e.g. laureusson) sees nothing, and every
`admins` member sees all owners**. If "only pittinic" must hold, only pittinic may be in `admins`
(an `owner=_admin` sentinel would not help: admins see it too).

Verified locally with the *rendered* chart configs, real images (Mimir 3.1.0, collector 0.154.0,
prom-label-proxy 0.13.0, Grafana 13.0.2) and the real payslip archive (2241 data points):
- the publisher's historical (2020→2026) samples are accepted by the finance tenant, and 7-year
  range queries work; the other tenants are untouched and nothing finance-related leaks into the
  `anonymous` tenant;
- the gateway stores `finance.*` series that have a concrete owner and **drops** those with no
  owner, `_shared`, `_admin` or an empty one (a missing owner would otherwise default to `_shared`,
  i.e. visible to everyone);
- through the label proxy: `X-Owner` for pittinic → series; for another user → none, even when the
  query names `owner="pittinic"` explicitly, and the label/series APIs are scoped too; admin regex → all;
- the dashboard (`observability/files/dashboards/finance/payslips.json`, PromQL) renders every
  panel in Grafana 13.0.2 through that chain; switching the caller to another user empties it.

**Not verified locally:** the live scope shim (needs LLDAP + Authelia + OIDC). It already serves
the `metrics` and `metrics-ai` datasources identically; the new `metrics-finance` datasource only
differs by its tenant header. First login on an environment is the acceptance test, and it must be
checked that the Grafana username equals `finance.publish.owner`.

Things that bit during the build (all handled in the chart):
- **Mimir's global 1 y retention and out-of-order window** would reject/delete 2020 payslips, so the
  tenant gets per-tenant overrides via a new `runtime.yaml` (`out_of_order_time_window`,
  `query_ingesters_within` = 20 y, `compactor_blocks_retention_period` = 0s).
- **429 `too_many_outstanding_requests`** on a 7-year dashboard: each panel query is split into ~2500
  daily sub-queries; 19 panels overflow the per-tenant queue. `max_query_parallelism: 2` for the
  tenant fixes it (40 concurrent 7 y queries: all 200). `split_queries_by_interval` is *not* a
  per-tenant limit in Mimir 3.1.0, and **an unknown key in `runtime.yaml` makes Mimir refuse to
  start**; only add keys that exist in the per-tenant `limits`.
- **Samples are immutable**: a different value for an existing (series, timestamp) is rejected, so a
  corrected historical figure cannot overwrite the old one. Timestamps are mid-month (15th 12:00 UTC)
  so calendar-aligned `$__range` windows never miss a month (windows are left-open).
- With `finance.publish.enable: false` (default) the observability chart renders **byte-identical**
  to before: no config change, no pod restart.

Switches (as deployed): `finance.publish.enable` is **true in `apps/base`** (prod-authoritative) and forced
**false on local** by `apps/local-overlay/finance-publish.yaml` (local does not run the observability stack).
That flag only turns on the *receiving* side (gateway pipeline, Mimir tenant overrides, datasource,
dashboard). Nothing is published until the **finance module itself** is enabled (`finance.enable: true`:
image, credentials, prod db volume, see *Enabling*) **and** `finance.publish.owner: <login>` is set in
platypod-sops (the chart refuses an empty owner). The publish step then runs at the end of every
`pp run payslips`, after the contract gate. Requires `observability.scopeShim.scopeMetrics: true` (the chart
refuses otherwise: without the shim every Grafana user could read the tenant; prod has it on).

**Purge and republish** (a corrected historical value, or a wrong first publish). Verified locally;
Mimir's tenant-deletion API only marks *blocks*, the ingester head must be removed too:

```sh
# scale Mimir to 0 (or stop it), then on its storage volume (subPath `mimir` of the apps volume):
rm -rf /storage/tsdb/finance /storage/blocks/finance
# start Mimir, then republish from Postgres (idempotent; no PDFs needed):
#   pp run payslips   (or a one-off job running the publish step)
```

Other tenants are untouched. Cost of the whole approach: the figures exist twice (Postgres is the
source of truth, Mimir a derived copy), the tenant grows unbounded (negligible: ~2.2 k samples),
and PromQL over monthly gauges is less natural than SQL (hence `last_over_time(x[45d])`
carry-forward and `sum_over_time(x[$__range])` range totals).

### Alternative kept, off by default: dedicated Grafana

A second Grafana (`finance-grafana`) behind Authelia forward-auth (`finance_user`/`admins`), OIDC with
`role_attribute_strict`, a `gold`-only Postgres role, secrets in a Secret. Verified on
`grafana-oss:13.0.2` (provisions datasource + dashboard, queries `gold`, denied on `silver`, 401 to
anonymous). Use it when you want SQL over the full model without the Mimir copy. Enable with
`finance.grafana.enable`, its OIDC client, and the `finance` entry in `security.accessGroups` (commented block in
`apps/base/values/security.yaml`; not active by default because it changes Authelia's rules) (hash with the `docker run … authelia crypto hash` command in
`apps/base/values/finance.yaml`).

## Backups (decided 2026-10-02)

Two independent mechanisms; the first is the one to restore from.

| | What | Where | Consistency |
|---|---|---|---|
| `finance-db-dump` (this chart) | `pg_dump --format=custom` of the whole database, nightly 03:45, 14 days kept | NFS `apps` share, `_db-backups/finance-logical/` | consistent snapshot; dump is re-read with `pg_restore --list` before it is kept |
| `localDb` `*-backup` CronJob (persistence module, only if `finance-db` is a `localDb` volume on prod) | `tar` of the live data directory, 03:15 | NFS `apps` share, `_db-backups/finance-db/` | **crash-consistent at best**; a fallback, not the thing to trust |

What is and is not at risk: the **payslip PDFs stay on the NAS**, and bronze→silver→gold is
re-derivable from them (`pp run payslips` is idempotent), so for payslips a lost database is a
re-run, not a loss. The dump matters for what is *not* re-derivable: `ops` history and lineage
events, and any future source that only exists as database rows. Prod NFS has no snapshots,
but dumps live on a different failure domain from the node-local database disk.

**Restore** (verified end to end on a throwaway instance: restore, row counts, grants, and
`pp test` contract checks all passed):

```sh
# 1. a fresh finance-db (the chart's init script creates the roles); database `finance` empty
# 2. copy the newest dump in and restore it (roles must exist; owners are not restored)
kubectl cp finance-YYYYMMDD-HHMMSS.dump <finance-db-pod>:/tmp/f.dump
kubectl exec <finance-db-pod> -- pg_restore --no-owner --exit-on-error -U finance_owner -d finance /tmp/f.dump
# 3. check grants and contracts: run the image once with the pipeline env, args: test
#    (= `pp test`, every ODCS contract against the live database)
```

**Not done:** encryption of dumps (deferred by choice; the dumps contain finance data in the
clear on the NAS), off-box copy, automated restore test in CI.

## Not done yet

- Flux `ImagePolicy` for the image; pipeline-health dashboard (metrics are emitted:
  `pipeline_run_duration_seconds`, `pipeline_rows_written`,
  `pipeline_contract_violations`, `pipeline_last_success_timestamp_seconds`).
- Alert on backup failure / stale dump (a failed Job is only visible via `kubectl`).
