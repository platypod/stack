# tempo (observability)

Traces store. Datasource uid `traces`; OTLP ingest via the gateway (`/v1/traces`).

- **Image:** `grafana/tempo:2.10.6` — **pinned, do not bump.** Tempo 3.0 is a breaking
  config rework (`field compactor not found` on the old config); upgrading needs the
  config ported first.

Currently lightly used — Claude Code emits logs + metrics, not OTLP spans, so the
event/transcript work doesn't populate Tempo.

## Memory / metrics-generator processors (2026-08-23)

The OTLP receiver was silently 404ing since this module's original deployment
(gateway's `otlphttp/tempo` exporter pointed at the wrong port) until the
2026-08-21 fix. Once real trace volume from mediarvester started arriving,
Tempo OOMKilled continuously (531 restarts in 47h) at its 512Mi limit.

Fix, two parts:
- Dropped the `local-blocks` metrics-generator processor
  (`overrides.defaults.metrics_generator.processors` in the chart's
  `config-map.yaml`). It's the memory-heaviest of the three processors because
  it keeps recent trace data resident to serve **TraceQL metrics** — ad-hoc
  aggregations like `{ span.http.status_code >= 500 } | rate()` computed
  on-the-fly from stored spans, as opposed to the fixed RED/service-graph
  metrics `span-metrics`/`service-graphs` stream out to Mimir. This
  deployment only needs the latter, so the ad-hoc-query capability wasn't
  worth the memory. If ad-hoc TraceQL metric queries in Grafana Explore are
  needed later, re-add `local-blocks` and raise the memory limit further.
- Bumped the memory limit 512Mi → 1Gi (`traces.yaml`), matching the same
  fix already applied to the OTel gateway for the same OOM pattern.

While checking the fix, found the `metrics_generator` remote-write to Mimir was
(and had likely always been) failing with 404 on every attempt: it posted to
`/api/v1/write`, which isn't a real Mimir route (the Prometheus-remote-write-
compatible endpoint is `/api/v1/push`). Fixed the path and added the
`X-Scope-OrgID: anonymous` header — Tempo pushes directly to Mimir rather than
through the OTel gateway, so it doesn't get the header the gateway's
`headers_setter` injects for everything else (Mimir has
`multitenancy_enabled: true`). Unrelated to the OOM; just adjacent and broken.

Also: `deployment.yaml` had no `checksum/config` annotation, so the ConfigMap
fix above didn't actually take effect on redeploy (pod kept running with the
old config until manually restarted). Added the annotation, matching every
other module's convention.
