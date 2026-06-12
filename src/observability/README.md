# observability module

OTLP-based telemetry pipeline: **OpenTelemetry Collector** → **Mimir** (metrics) /
**Loki** (logs) / **Tempo** (traces), visualised in **Grafana**, with
**Uptime-Kuma** for black-box uptime checks.

## Pipeline

Apps and the collector speak **OTLP**. The OpenTelemetry Collector runs in two
roles (`*-collector` agent + `*-gateway`) and fans telemetry out to the three
backends.

## Mimir (metrics)

Replaced VictoriaMetrics. **Mimir 3.x normalizes OTel names** (dots → underscores),
so dashboards/queries must use the underscore form. Endpoints:

- Query (Grafana datasource): `/prometheus`
- OTLP ingest: `/otlp/v1/metrics`

Mimir 3.1 reads the older TSDB written by earlier versions — upgrades are
data-safe.

## Tempo (traces)

**Pinned to 2.10.6.** Tempo 3.0 is a breaking config rework (`field compactor not
found` on the old config) — do not bump without porting the config.

## Grafana

Login via Authelia **OIDC** (`generic_oauth`). Datasources for Mimir/Loki/Tempo
are provisioned.

## Uptime-Kuma

Own admin login (`group:dev`). **Pinned to the 1.23.x stable line** — 2.x is a
beta that dropped the Socket.io API the seed Job relies on.

A post-install/upgrade hook Job (`uptime-kuma-setup`) creates the admin and seeds
the monitors declared in `uptimeKuma.monitors`. The monitors are **in-cluster**
HTTP checks (ClusterIP, not the public URL) so they bypass Authelia and report
real app health instead of a 302 to the login page. The Job is idempotent
(monitors matched by name); add/remove entries in the values file to manage them.

## Exporters

App-specific exporters (e.g. `prometheus-json-exporter` for Jellyfin,
`transmission-exporter`, `prometheus-snmp-exporter`) feed Prometheus-format
metrics into the pipeline. A backlog item tracks moving these into per-app
sidecars — see [docs/TODO.md](../../docs/TODO.md).
