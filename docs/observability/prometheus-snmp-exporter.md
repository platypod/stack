# prometheus-snmp-exporter (observability)

SNMP exporter for the **Synology NAS** — scraped by the gateway's `synologySnmp`
Prometheus job (gated by `observability.otelCollector.receivers.synologySnmp.enable`)
and visualised by the `nas.json` dashboard.

- **Image:** `prom/snmp-exporter:v0.29.0`.
- **Modules:** `if_mib`, `synology`; auth `synology_v3` (SNMPv3).
- **Target:** the NAS SNMP address (`…receivers.synologySnmp.url`); relabeled so the
  scrape hits the exporter with `__param_target` = the NAS.

Optional component — only runs when the SNMP receiver is enabled in values.
