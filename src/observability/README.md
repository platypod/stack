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

App-specific exporters (e.g. `prometheus-json-exporter` for Jellyfin and FX
rates, `transmission-exporter`, `prometheus-snmp-exporter`) feed Prometheus-format
metrics into the pipeline. A backlog item tracks moving these into per-app
sidecars — see [docs/TODO.md](../../docs/TODO.md).

## Claude Code usage telemetry

The laptop's Claude Code CLI pushes its own OTLP telemetry into this cluster, plus
full session transcripts (see below). Two provisioned dashboards visualise it, both
in the **Claude** Grafana folder (`files/dashboards/claude/`, mounted via a
dedicated provider):

- **Claude - Native indicators** (`claude-native.json`) — cost/tokens/sessions,
  rates, log panels: everything from the OTLP telemetry.
- **Claude - Custom indicators** (`claude-custom.json`) — built on the shipped
  transcripts: tool-usage breakdown, tool calls over time, messages by role,
  activity by project, a named-**session** table, and a content panel showing the
  actual tool I/O and responses. Driven by the `project`/`session` template
  variables (which is why `session_title`/`project` are promoted to Loki indexed
  labels — see the transcripts section).

### Ingestion (external OTLP)

Claude Code exports over **OTLP/gRPC** to
`opentelemetry-collector-grpc.platypod.ovh:443`, authenticated through Authelia
with a Basic-auth LLDAP service account (`otel-telemetry`). The dedicated
`forward-auth-basic` Authelia endpoint + `authelia-basic` Traefik middleware +
`gateway/grpc-ingress-route.yaml` carry it to the gateway's OTLP gRPC port. Both
**logs** (→ Loki) and **metrics** (→ Mimir) flow over this one path.

Client config lives in the laptop's `~/.claude/settings.json` `env` block
(`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_*` endpoint/headers).

### Metrics: cumulative temporality is mandatory

Claude Code defaults to **delta** temporality; **Mimir's OTLP ingestion only
accepts cumulative** and rejects the whole payload with
`HTTP 400 … invalid temporality and type combination for metric
"claude_code.session.count"` (visible in the gateway `otlphttp/mimir` exporter
logs). Logs are unaffected. The client **must** set
`OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative`, after which
`claude_code_session_count` / `cost_usage` / `token_usage` / `active_time_total`
appear in Mimir. (Server-side alternative if ever needed: a `deltatocumulative`
processor in the gateway `metrics/otlp` pipeline.)

### Logs in Loki

Loki's OTLP endpoint indexes resource attributes as labels: the stream is
`{service_name="claude-code-desktop"}` (NOT `service_namespace`). The
per-event breakdown uses `event_name` (structured metadata):
`sum by (event_name) (count_over_time({service_name="claude-code-desktop"}[$__auto]))`.

**Content vs metadata.** Claude Code telemetry is mostly *metadata*: tool and API
events carry `tool_name`, `success`, `duration_ms`, byte **sizes**
(`tool_input_size_bytes`, `tool_result_size_bytes`) and token counts — **never the
actual tool input/result or model response text**. The only user-content field is
the **prompt**, `<REDACTED>` unless the client sets `OTEL_LOG_USER_PROMPTS=1` (then
the `user_prompt` event carries the real text — a privacy trade-off, since prompt
content then lands in Loki). The flag only affects events emitted after a Claude
Code restart; past events stay redacted.

### Full transcripts (content + DAG) — `make ship-transcripts`

Telemetry is metadata-only (above), so the actual tool I/O and model responses are
shipped separately from the on-disk session transcripts
(`~/.claude/projects/*/*.jsonl`) by [`bin/ship-transcripts`](../../bin/ship-transcripts),
run via `make ship-transcripts`. It is **manual, no daemon**: each run tracks
per-file byte offsets (`~/.claude/.platypod-transcript-shipper.json`) and ships
only new lines — first run backfills, later runs tail. `ARGS="--dry-run|--limit
N|--reset|--projects=GLOB"`.

- **Transport:** reuses the existing OTLP/gRPC gateway + Basic auth read straight
  from `~/.claude/settings.json` — no new ingress, no new credentials. Lands as
  `{service_name="claude-code-transcripts"}`; the full (redacted) JSONL line is the
  body, with `session_id`/`session_title`/`type`/`uuid`/`parent_uuid`/`tool_name`/
  `tool_use_id`/`project` as structured metadata (`parent_uuid → uuid` links the
  message chain). `session_title`/`project` are promoted to indexed labels (Loki
  `otlp_config`) so they can drive Grafana dropdowns.
- **Redaction:** harvests the literal secret values from `stack/values/**/*.yaml`
  (keys matching password/secret/token/apiKey/jwt/…) and redacts those exact
  strings, plus generic `Authorization:`/`PRIVATE KEY` shapes. This catches the
  *known* secrets precisely; it cannot catch an arbitrary secret pasted/`cat`'d
  from outside the values files — transcripts are inherently sensitive, so Loki
  access stays behind Authelia.
- **Old samples:** historical transcripts are weeks/months old, so Loki's
  `limits_config` sets `reject_old_samples: false` + `max_query_length: 0` (it
  otherwise drops anything older than ~1 week). The Loki deployment carries a
  `checksum/config` annotation so such config edits actually restart it.
- **Known limit:** a dropped batch on a transient gRPC error still advances the
  file offset, so re-run with `ARGS="--reset"` to re-ship (Loki dedupes exact
  duplicate lines).

### Derived metrics (Mimir) — `claude_tx_*`

Telemetry and transcript *logs* are metadata/content; for **aggregatable** insight
the shipper also derives numeric metrics from the structured transcript fields and
pushes them to Mimir over the same OTLP gateway. Dashboards built on these use
PromQL (fast, alertable) instead of LogQL line-counting.

They are emitted as **gauges stamped at each message's own event time**, not
process-clock counters — because Mimir's OTLP ingestion requires *cumulative*
temporality (rejects deltas) and the shipper backfills/tails incrementally, so a
gauge carrying the per-message value at its timestamp is the only shape that stays
idempotent across re-runs and backfill. Aggregate in PromQL with `sum_over_time`
(counts/tokens/cost), `quantile_over_time` (latency), or max−min of the epoch gauge
(session duration). The standard OTel metrics SDK won't backdate datapoints, so the
shipper builds OTLP datapoints by hand (`emit_metrics` in `bin/ship-transcripts`).

| Metric | Labels | Meaning |
|---|---|---|
| `claude_tx_tokens` | `kind`(input/output/cache_read/cache_write), `model`, `project`, `session_*` | per-message token counts |
| `claude_tx_cost_usd` | `model`, `project`, `session_*` | per-message cost (token kinds × per-model rates; cache read 0.1×, 5m write 1.25×, 1h write 2× input) |
| `claude_tx_tool_calls` | `tool_name`, `project`, `session_*` | tool invocations |
| `claude_tx_tool_latency_seconds` | `tool_name`, … | tool_use→tool_result delta (DAG-matched) |
| `claude_tx_tool_errors` | `tool_name`, … | `is_error` tool results |
| `claude_tx_turns` | `project`, `session_*` | human turns (non-tool-result user messages) |
| `claude_tx_stop_reason` | `stop_reason`, … | assistant stop reasons |
| `claude_tx_event_epoch_seconds` | `project`, `session_*` | message event epoch → session duration / time-of-day |

The per-model rate table lives in `bin/ship-transcripts` (`MODEL_RATES`); update it
when pricing changes. Unknown models fall back to Opus-tier. **Next step:** rebuild
`claude-custom.json` panels on these PromQL series (exec-summary, efficiency,
patterns rows) and keep one Loki panel for the readable transcript content.

### Cost currency conversion (live FX)

The cost panels convert USD → a selectable display currency using **real ECB
rates**, not a relabel:

- The `fx` module in `prometheus-json-exporter` scrapes
  `https://api.frankfurter.dev/v1/latest?base=USD` (daily ECB data, no API key)
  and emits `usd_fx_rate{currency="EUR"}`, `…="JPY"`, etc.
- The collector `prometheus/fx` scrape job (5m interval) + `metrics/fx` pipeline
  ship those into Mimir.
- The dashboard `currency` template variable (ISO-code value, symbol as display
  text) multiplies cost by `(sum(usd_fx_rate{currency="$currency"}) or vector(1))`
  — the `or vector(1)` makes **USD fall back to ×1** (USD is the feed base and is
  absent from the rates).

Conventions / gotchas worth knowing before editing:

- **Same metric name ⇒ identical `help`.** json-exporter panics
  (`inconsistent label names or help`) if `usd_fx_rate` entries differ in `help`;
  repeat the exact same string on every currency entry.
- **frankfurter.app 301-redirects** and the exporter doesn't follow redirects by
  default — use the `.dev` host and `http_client_config.follow_redirects: true`.
- **First-scrape jitter.** Prometheus spreads the first scrape across the whole
  `scrape_interval`, so a long interval leaves `usd_fx_rate` (and the cost panels)
  empty for that long after any collector restart — hence 5m, not 1h.
- **Grafana does not interpolate the panel `unit` field.** `unit:
  "currency${currency}"` renders literally. The value uses a numeric unit and the
  currency symbol is placed in the **panel title** via `${currency:text}` (titles
  *are* interpolated).
- **Custom-variable option syntax is `displayText : value`** (symbol before the
  colon, ISO code after — e.g. `€ : EUR`). Reversing it makes `$currency` the
  symbol, so `usd_fx_rate{currency="€"}` never matches and every currency silently
  shows the ×1 USD fallback. To add a currency: add a `<symbol> : <ISO>` option to
  the `currency` variable *and* a matching `usd_fx_rate` entry in the json-exporter
  `fx` module.
