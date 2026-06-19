# prometheus-json-exporter (observability)

prometheus-community json_exporter — turns JSON HTTP endpoints into Prometheus
metrics. Scraped by the [gateway](otel-collector-gateway.md) via `/probe?module=…`.

- **Image:** `quay.io/prometheuscommunity/json-exporter:v0.7.0`.
- **Modules** (`config.yml`):
  - **`jellyfin`** — playback metrics from the Jellyfin API (auth header).
  - **`fx`** — USD→currency ECB rates from `api.frankfurter.dev/v1/latest?base=USD`,
    emitting `usd_fx_rate{currency=…}` (one entry per currency). Feeds the Claude cost
    dashboard's live conversion.

## Gotchas
- **Same metric name ⇒ identical `help`** across every entry, or the prometheus client
  **panics** (`inconsistent label names or help`).
- `follow_redirects: true` is needed for hosts that 301 (frankfurter`.app` → `.dev`).
- See [[grafana-claude-cost-currency]] for the FX setup.
