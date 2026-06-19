# loki (observability)

Logs store. Single-binary, filesystem storage, TSDB schema v13.

- **Image:** `grafana/loki:3.7.2`.
- **Ingest:** OTLP at `/otlp/v1/logs` (via the gateway). Query datasource uid `logs`.
- **Tenant:** `auth_enabled` off → default tenant **`fake`** (delete/label APIs need
  `X-Scope-OrgID: fake`).
- **Deployment carries a `checksum/config` annotation** — added because config-map
  edits were otherwise silently ignored until the pod happened to restart.

## Non-default `limits_config`
- `reject_old_samples: false` — accept back-dated samples (historical Claude Code
  transcripts are weeks old; default drops anything >~1 week).
- `max_query_length: 0` — allow querying the full history (default caps ~30d).
- `otlp_config.log_attributes` promotes `session_title`, `project`, `tool_name` to
  **indexed labels** so Grafana `label_values()` can drive dropdowns; everything else
  stays structured metadata.
- `deletion_mode: filter-and-delete` + `retention_period: 8760h` + a **compactor**
  (`retention_enabled`, `delete_request_store: filesystem`,
  `delete_request_cancel_period: 10m`) → the delete API works for dropping streams.
  Retention is effectively infinite (8760h) so only explicit deletes act.

## Gotchas
- The delete API is **time-range based on log timestamp**, async, and only processes
  after `delete_request_cancel_period`. Re-shipping same-timestamped data during that
  window gets deleted too. See [[claude-transcript-shipper]].
- OTLP label promotion: only `service_name` is indexed by default — hence the explicit
  `otlp_config` above.
