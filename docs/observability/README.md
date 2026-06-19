# observability module

OTLP telemetry pipeline → Grafana. The module's deep-dive lives in
[src/observability/README.md](../../src/observability/README.md); these files are the
per-service reference.

## Services
- [grafana](grafana.md) — dashboards + Explore (OIDC login).
- [mimir](mimir.md) — metrics store (Prometheus-compatible).
- [loki](loki.md) — logs store.
- [tempo](tempo.md) — traces store.
- [otel-collector-gateway](otel-collector-gateway.md) — single-replica gateway: OTLP
  ingest + cluster/scrape pipelines → backends.
- [otel-collector-daemonset](otel-collector-daemonset.md) — per-node collectors
  (kubeletstats).
- [prometheus-json-exporter](prometheus-json-exporter.md) — Jellyfin + FX-rate scrapes.
- [prometheus-snmp-exporter](prometheus-snmp-exporter.md) — Synology SNMP.
- [uptime-kuma](uptime-kuma.md) — black-box uptime.

## Jobs
- [uptime-kuma-setup-job](uptime-kuma-setup-job.md) — seeds admin + monitors.
