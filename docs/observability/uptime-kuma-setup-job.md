# uptime-kuma-setup (Job)

Post-install/upgrade hook that creates the Uptime-Kuma admin and seeds the monitors
declared in `uptimeKuma.monitors`.

- **Template:** `src/observability/templates/observability/uptime-kuma/uptime-kuma--setup-job.yaml`
- **Idempotent:** monitors matched by name; add/remove entries in values to manage them.
- **Uses the Socket.io seed API** — which is why Uptime-Kuma is pinned to **1.23.x**
  (2.x removed it). See [uptime-kuma](uptime-kuma.md).
- Seeded monitors are **in-cluster (ClusterIP)** checks so they measure real app health,
  not Authelia's login redirect.
