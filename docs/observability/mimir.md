# mimir (observability)

Metrics store (replaced VictoriaMetrics). Prometheus-compatible.

- **Image:** `grafana/mimir:3.1.0` (reads older TSDB — upgrades are data-safe).
- **Endpoints:** query (Grafana datasource) `/prometheus`; OTLP ingest
  `/otlp/v1/metrics`.
- **Name normalization:** Mimir lowercases/normalizes OTel metric names (dots →
  underscores), e.g. `system.cpu.time` → `system_cpu_time` — dashboards must query the
  underscore form.
- **Tenant:** `auth_enabled` off → default tenant; queries need `X-Scope-OrgID:
  anonymous`.

## Gotchas
- **OTLP ingestion only accepts CUMULATIVE temporality.** Delta-temporality metrics
  are rejected with `HTTP 400 invalid temporality and type combination` and silently
  dropped. Claude Code defaults to delta → must set
  `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative` client-side. See
  [decisions.md](../decisions.md). (Server-side alternative: a `deltatocumulative`
  processor in the gateway.)
- Mimir derives `job`/`instance` from `service.name`/`service.instance.id`; datapoint
  attributes can't override those reserved labels.
- **Historical/backfilled queries can 500 with `err-mimir-bucket-index-too-old`.**
  Backfilled data (timestamps in the past) is queried via the store-gateway path,
  which reads the bucket index — Mimir rejects an index staler than its default 1h.
  A single monolithic instance's compactor cleanup can lag past that under load. Fix
  (`observability/mimir/config-map.yaml`):
  ```yaml
  blocks_storage:
    bucket_store:
      sync_interval: 5m
      bucket_index:
        max_stale_period: 24h
  compactor:
    cleanup_interval: 5m
  ```
  Backfilling historical data at all also needs three per-tenant `limits` widened
  from the near-real-time defaults: `out_of_order_time_window` (else back-dated
  samples are dropped as `sample-timestamp-too-old`), `ingestion_rate` +
  `ingestion_burst_size` (else a large backfill burst is `rate_limited`), and
  `query_ingesters_within` (the querier only consults ingesters for their default
  in-memory OOO window — a historical range otherwise returns nothing even though
  ingestion succeeded). Diagnose via `/metrics`:
  `cortex_discarded_samples_total{reason=...}` and
  `cortex_ingester_tsdb_out_of_order_samples_appended_total`. An **instant** query
  can mislead on a sparse historical series — verify with a range function instead,
  e.g. `count(count_over_time(some_metric[400d]))`.
