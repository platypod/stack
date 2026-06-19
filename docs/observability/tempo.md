# tempo (observability)

Traces store. Datasource uid `traces`; OTLP ingest via the gateway (`/v1/traces`).

- **Image:** `grafana/tempo:2.10.6` — **pinned, do not bump.** Tempo 3.0 is a breaking
  config rework (`field compactor not found` on the old config); upgrading needs the
  config ported first.

Currently lightly used — Claude Code emits logs + metrics, not OTLP spans, so the
event/transcript work doesn't populate Tempo.
