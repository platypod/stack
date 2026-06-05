# core module

The foundation of the stack: reverse proxy and landing page. All other modules depend on this one being deployed first.

## Traefik

Reverse proxy and TLS termination point for all services.

- Listens on `:443` (entrypoint `https`) and `:9999` (entrypoint `traefik`, dashboard).
- All services are routed via `IngressRoute` CRDs (not standard `Ingress`).
- TLS behaviour is env-dependent:
  - **dev** — serves a self-signed wildcard cert for `*.platypod.local` via a `TLSStore default` pointing at the `platypod-local-tls` secret. `certResolver` is omitted from IngressRoutes.
  - **prod** — resolves certs via ACME/Let's Encrypt (TLS challenge) using the `letsencrypt` resolver. `certResolver: letsencrypt` is set on each IngressRoute.
- Exposes a `LoadBalancer` service; MetalLB assigns an IP from the pool configured in the cluster.
- RBAC: needs a `ClusterRole` to watch `IngressRoute`, `Middleware`, and `TLSStore` resources across the cluster.

### File provider

A ConfigMap mounts a file-provider config at `/file-providers/jellyfin-local-proxy.yaml`. This lets Traefik route to a Jellyfin instance running directly on the host (outside K8s) when `jellyfin.proxy.enable=true`.

## Homepage

Kubernetes-aware dashboard — auto-discovers services from the cluster and shows them as a home page.

- Reads service annotations and a mounted ConfigMap for layout and bookmarks.
- Exposed at `{{ traefik.host }}` behind the Authelia SSO middleware.
- Needs a `ClusterRole` to list pods, services, and ingresses across namespaces.
