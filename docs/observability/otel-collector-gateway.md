# otel-collector-gateway (observability)

Single-replica OpenTelemetry Collector — the cluster's OTLP front door and the owner
of all whole-cluster scrape pipelines. Fans telemetry out to Mimir/Loki/Tempo.

- **Image:** `otel/opentelemetry-collector-contrib:0.154.0`.
- **Runs single-replica** for the `k8s_cluster` receiver (whole-cluster state must
  have exactly one owner or counts double). Per-node usage comes from the
  [daemonset](otel-collector-daemonset.md) instead.

## Receivers / pipelines
- **OTLP** (gRPC `4317`, HTTP `4318`) — external clients (Claude Code telemetry, the
  transcript shipper) push here through the Authelia Basic-auth gRPC ingress. Logs →
  Loki, metrics → Mimir, traces → Tempo.
- **Prometheus scrapes:** traefik, authelia, transmission, k8s_cluster, and the
  json-exporter modules: **jellyfin** (gated) and **fx-rates** (USD→currency from
  `api.frankfurter.dev`, 5m interval). Optional: synology SNMP, jellyfin native.
- Each pipeline tags `gateway-receiver`; k8s_cluster promotes pod/node/etc. resource
  attrs to datapoint labels (else every series is anonymous).
- Exporters: `otlphttp/mimir` (`/otlp/v1/metrics`), `otlphttp/loki` (`/otlp`),
  `otlphttp/tempo` (`/v1/traces`).

## Gotchas
- Metrics export to Mimir fails on **delta temporality** — see [mimir](mimir.md).
- Adding an FX/JSON scrape: identical `help` per metric name (json-exporter panics
  otherwise) and a short `scrape_interval` (Prometheus jitters the first scrape across
  the whole interval). See [[grafana-claude-cost-currency]].
