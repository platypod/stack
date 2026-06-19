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
  [[otel-telemetry-auth]]. (Server-side alternative: a `deltatocumulative` processor
  in the gateway.)
- Mimir derives `job`/`instance` from `service.name`/`service.instance.id`; datapoint
  attributes can't override those reserved labels.
