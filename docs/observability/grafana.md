# grafana (observability)

Dashboards + Explore. Login via Authelia **OIDC** (`generic_oauth`).

- **Image:** `grafana/grafana-oss:13.0.2`.
- **Memory:** request 192Mi / **limit 384Mi**. A heavyweight panel plugin
  (e.g. volkovlabs-echarts) OOMKills it at this limit — bump to ~768Mi if you add
  one. We removed that plugin and reverted to 384Mi (stock panels only).
- **Datasources** (provisioned, fixed uids): `metrics` (Mimir), `logs` (Loki),
  `traces` (Tempo). Dashboards reference these uids.
- **Dashboard folders** (file providers): `Platform`
  (`files/dashboards/*.json`), `Media`, and **`Claude`**
  (`files/dashboards/claude/*.json`, own configmap + provider). Each is a whole-dir
  mount; add a JSON file and it ships.
- `checksum/config` + `checksum/dashboards` annotations restart Grafana on changes.

## Gotchas
- OIDC back-channel: a `hostAlias` maps the Authelia hostname to the Traefik LB IP so
  the in-cluster token/userinfo calls resolve.
- **Grafana does not interpolate the panel `unit` field** (put dynamic symbols in the
  title via `${var:text}`). See [[grafana-claude-cost-currency]].
- Data links use `/d/<uid>?${__url_time_range}&${__all_variables}&var-X=${value}` for
  click-to-filter / cross-dashboard drill-downs.
