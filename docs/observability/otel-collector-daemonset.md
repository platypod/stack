# otel-collector-daemonset (observability)

Per-node OpenTelemetry Collectors — one pod per node, scraping that node's kubelet.

- **Image:** `otel/opentelemetry-collector-contrib:0.154.0`.
- **Role:** `kubeletstats` receiver → per-pod/per-container CPU, memory, network,
  filesystem usage. Tagged `node_collector_receiver="kubeletstats"`; exported to Mimir
  (e.g. `container_cpu_usage`, `k8s_pod_*`) — these power the Workloads / Pod Detail
  dashboards.
- **Why a DaemonSet (not the gateway):** usage is per-node, so each node scrapes its
  own kubelet; whole-cluster *state* stays on the single-replica
  [gateway](otel-collector-gateway.md).
