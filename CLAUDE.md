# platypod/services

Kubernetes workload stack. Each service is a Helm chart deployed via Helmfile.

---

## Structure

```
src/<module>/           # Helm chart per module (Chart.yaml committed)
  templates/<service>/  # K8s manifests (Deployment, Service, IngressRoute, etc.)
values/
  default/<module>/     # Default values — .yaml.gotmpl (Go templates, env-agnostic)
  dev/values.yaml       # Dev env overrides
  prd/values.yaml       # Prod env overrides
images/<name>/          # Custom Docker images (built and pushed to GHCR)
  Dockerfile
bin/                    # Shell scripts
Makefile                # Primary interface — see below
helmfile.yaml.gotmpl    # Environments, value loading order, release dependency graph
```

## Modules

| Dir | Services |
|-----|----------|
| `persistence` | PV/PVC (local-storage or NFS) |
| `core` | Traefik, Homepage |
| `security` | Adguard, Authelia, CyberChef |
| `observability` | OtelCollector, Loki, Tempo, VictoriaMetrics, Grafana |
| `dev-tools` | Bookstack, PostgreSQL, IT-Tools, WhoAmI, DBeaver |
| `files` | Transmission, QBitTorrent, Deluge |
| `media` | Jellyfin, Prowlarr, Radarr, Sonarr, Readarr, Bazarr, Jellyseerr, Flaresolverr, youtube-downloader |
| `games` | RommApp, Pokeclicker |

---

## Dev lifecycle (first time)

Prerequisites: a running dev cluster (`make apply ENV=dev` in `infra-as-code/k8s-in-vms/`).
The Makefile auto-discovers the kubeconfig at `../infra-as-code/k8s-in-vms/.generated/dev/kubeconfig`.

```sh
make install-deps    # helm, helmfile, kubectl, helm-diff
make setup-dev       # mkcert CA + TLS secret + CRDs + core deploy + dnsmasq (one-time per machine)
make deploy          # full stack
```

`make setup-dev` runs these steps in order:
1. `setup-dev-tls` — installs mkcert, trusts the local CA in macOS Keychain (prompts for sudo), generates `*.platypod.local` cert, stores it as the `platypod-local-tls` K8s secret.
2. `install-crds` — applies Traefik CRD manifests so IngressRoute and Middleware objects are recognised.
3. `deploy MODULE=core` — deploys Traefik (gets a `192.168.122.200+` IP from MetalLB) and Homepage.
4. `setup-dev-dns` — installs dnsmasq, adds `address=/.platypod.local/<traefik-lb-ip>`, creates `/etc/resolver/platypod.local`, restarts dnsmasq. Traefik's LB IP is auto-detected from kubectl.

After `setup-dev`, re-run `make deploy` to bring up the full stack.

### Day-to-day dev commands

```sh
make deploy                  # sync full stack
make deploy MODULE=core      # sync a single module
make destroy MODULE=core     # uninstall a single module
make diff MODULE=core        # dry-run diff
make status                  # list deployed releases
```

### After a cluster restart

The kubeconfig and the TLS secret survive cluster reboots (the secret lives in etcd). The dnsmasq entry is permanent. Nothing to redo unless you rebuilt the cluster from scratch (`make destroy` + `make apply` in k8s-in-vms), in which case re-run `make setup-dev`.

---

## Prod lifecycle

```sh
make install-deps
make install-crds ENV=prd
make deploy ENV=prd
```

Prod uses public DNS (`platypod.ovh`) and ACME/Let's Encrypt for TLS — no mkcert step needed. The ACME email and endpoint are in `values/prd/values.yaml`.

---

## Dev vs prod differences

| Concern | dev | prod |
|---------|-----|------|
| K8s namespace | `dev-platypod` | `prd-platypod` |
| Domain | `platypod.local` | `platypod.ovh` |
| TLS | Self-signed wildcard via mkcert + `TLSStore default` | ACME (Let's Encrypt production, TLS challenge) |
| `certResolver` in IngressRoutes | omitted (TLSStore default picks up the cert) | `letsencrypt` |
| Storage backend | Local hostPath on worker (`/var/local/platypod/volumes/`) | NFS from Synology (`192.168.1.30`) |
| Storage PV node affinity | label `platypod.io/local-storage=true` (applied by Terraform) | n/a (NFS is cluster-wide) |
| DNS resolution | dnsmasq on laptop | Public DNS |

---

## Key conventions

- Services are exposed via Traefik `IngressRoute` CRDs (not standard `Ingress`).
- SSO is handled by an Authelia `Middleware` referenced from each IngressRoute.
- Values files use Go template syntax for cross-references: `{{ .Values.some.key }}`. The `.gotmpl` extension signals helmfile to render them before passing to Helm.
- Values are loaded in dependency order in `helmfile.yaml.gotmpl` — foundational files first, cross-module aggregators (authelia) last, env override last of all.
- Module release order is declared via `needs:` in `helmfile.yaml.gotmpl`; helmfile enforces it.
- Custom images live in `images/` and are pushed to `ghcr.io/pittinic/<name>:<tag>`.

### Pitfalls

**Always wrap template-valued strings with `tpl`.**  
If a value itself contains a Go template expression (e.g. `host: "{{ .Values.foo.label }}.{{ .Values.traefik.domain }}"`), referencing it as `{{ .Values.foo.host }}` in a template renders the literal string. You must use `{{ tpl .Values.foo.host . }}` to evaluate it. Omitting `tpl` produces unrendered `{{ ... }}` strings in the deployed manifest — a class of bug that is silent at `helm template` time but broken at runtime.

**Helm server-side apply rejects `tls: {}` on Traefik IngressRoute CRDs.**  
When `traefik.tls.selfSigned=true`, IngressRoutes must NOT use `tls: {}` (empty object) — Helm's SSA serialises it as JSON null, which the CRD schema rejects. Use `tls.store.name: default` instead, which explicitly references the `TLSStore` and satisfies SSA.

**Pods that mount a ConfigMap must have a checksum annotation to auto-restart on config changes.**  
Kubernetes does not restart pods when a mounted ConfigMap is updated. Without a checksum annotation on the pod template, config changes are silently ignored until the next manual rollout. Pattern:
```yaml
template:
  metadata:
    annotations:
      checksum/config: {{ include (print $.Template.BasePath "/<config-map-file>.yaml") . | sha256sum }}
```
Authelia has this; apply the same pattern to any other pod whose config is stored in a ConfigMap.

---

## Adding a new service

1. Create `src/<module>/templates/<service>/` with K8s manifests.
2. Add `values/default/<module>/<service>.yaml.gotmpl` with default values.
   Use `{{ .Values.x.y }}` to cross-reference other values.
3. Add the new file to the correct position in the `helmfile.yaml.gotmpl` values list
   (after any values it references, before authelia).
4. Override in `values/<env>/values.yaml` as needed.
5. Follow the pattern: Deployment → Service → IngressRoute (+ Authelia middleware if auth needed).

## Adding a new custom image

1. Create `images/<name>/Dockerfile`.
2. Build and push: `make build IMAGE=<name> VERSION=<tag>`
3. Reference as `ghcr.io/pittinic/<name>:<tag>` in the values file.

---

## Environment variable

`PLATYPOD__HELM__DEFAULT_ENV=dev` — used by `bin/helm.sh` functions as the default env
when `--env` is not passed. The Makefile uses `ENV=dev` instead and passes it directly
to helmfile; this variable is only relevant if you source `bin/helm.sh` directly.
