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
| `security` | Adguard, Authelia, LLDAP, CyberChef, Vaultwarden, Uptime Kuma |
| `observability` | OtelCollector, Loki, Tempo, VictoriaMetrics, Grafana |
| `dev-tools` | Bookstack, Wiki.js, PostgreSQL, IT-Tools, WhoAmI, DBeaver |
| `files` | Transmission, QBitTorrent, Deluge |
| `media` | Jellyfin, Prowlarr, Radarr, Sonarr, Readarr, Bazarr, Jellyseerr, Flaresolverr, Mediarvester, PostgreSQL |
| `games` | RommApp, Pokeclicker |

---

## Dev lifecycle (first time)

Prerequisites: a running dev cluster (`make apply ENV=dev` in `infra/k8s-in-vms/`).
The Makefile auto-discovers the kubeconfig at `../infra/k8s-in-vms/.generated/dev/kubeconfig`.

```sh
make install-deps    # helm, helmfile, kubectl, helm-diff
make setup-dev       # mkcert CA + TLS secret + CRDs + core deploy + dnsmasq (one-time per machine)
make deploy          # full stack
```

`make setup-dev` runs these steps in order:
1. `setup-dev-tls` — installs mkcert, trusts the local CA in macOS Keychain (prompts for sudo), generates `*.platypod.local` cert, stores it as the `platypod-local-tls` K8s secret.
2. `install-crds` — applies Traefik CRD manifests so IngressRoute and Middleware objects are recognised.
3. `deploy MODULE=core` — deploys Traefik (gets a `192.168.122.200+` IP from MetalLB) and Homepage.
4. `setup-dev-dns` — sets the system DNS to Adguard's LoadBalancer IP (`192.168.122.201`) with `1.1.1.1` as fallback, cleans up any leftover dnsmasq config. Adguard handles the `*.platypod.local → 192.168.122.200` (Traefik) rewrite internally. When the cluster is suspended, internet DNS falls through to `1.1.1.1`; `*.platypod.local` simply won't resolve.

After `setup-dev`, the base stack (persistence + core + security) is running.
Deploy additional modules individually as needed — not all at once:

```sh
make deploy MODULE=observability   # add when you need dashboards
make deploy MODULE=media           # add when you need Jellyfin/Sonarr/etc.
# etc.
```

Running all modules simultaneously on the 4 GB dev worker is marginal.
The base stack is the stable working set; extras are opt-in.

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

### Accessing persistent volume data (dev)

Talos has no SSH, so you can't mount the worker's filesystem directly. Use
`talosctl` to browse and transfer files on the worker node (`192.168.122.102`):

```sh
export TALOSCONFIG=../infra/k8s-in-vms/.generated/dev/talosconfig

# Browse
talosctl -n 192.168.122.102 ls /var/local/platypod/volumes/
talosctl -n 192.168.122.102 ls /var/local/platypod/volumes/apps/

# Read a file
talosctl -n 192.168.122.102 read /var/local/platypod/volumes/apps/some-file

# Copy from node to local machine
talosctl -n 192.168.122.102 cp /var/local/platypod/volumes/apps/some-file ./some-file

# Copy from local machine to node
talosctl -n 192.168.122.102 cp ./some-file /var/local/platypod/volumes/apps/some-file
```

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
- Custom images live in `images/` and are pushed to `ghcr.io/platypod/<name>:<tag>`.

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

**Helm Go templates parse `{{ }}` everywhere — including YAML comments.**  
A YAML comment like `# reference {{MY_VAR}}` will cause a template parse error
(`function "MY_VAR" not defined`). Escape literal braces in comments using a
string literal: `{{ "{{MY_VAR}}" }}`, or simply avoid `{{ }}` in comments.

**The linuxserver Transmission image always overwrites RPC whitelist settings.**  
The linuxserver init script hardcodes `rpc-whitelist: "127.0.0.1,::1"` and
`rpc-host-whitelist: ""` (empty = block all hosts) on every container start,
regardless of what is in `settings.json`. This blocks access from other pods
(e.g. Homepage widget) and from Traefik.  
Fix: use a `lifecycle.postStart` hook that calls the Transmission RPC from
`localhost` (which bypasses the IP whitelist) to disable both checks:
```yaml
lifecycle:
  postStart:
    exec:
      command: ["/bin/sh", "-c", "...curl session-set rpc-whitelist-enabled=false..."]
```
See `src/files/templates/transmission/transmission--deployment.yaml` for the
full hook.

**LLDAP does not update the admin password on restart.**  
`LLDAP_LDAP_USER_PASS` only takes effect when the admin user is first created
(i.e. on a fresh database). If the database already exists, changing the env
var has no effect. To change the admin password on a running instance, use:
```sh
kubectl -n <ns> run -it --rm pw --image=lldap/lldap:stable --restart=Never \
  --command -- /app/lldap_set_password \
  --base-url http://lldap:<port> \
  --admin-username admin --admin-password <current> \
  --username admin --password <new>
```
Keep `lldap.adminPassword` in values in sync with the actual DB password.

---

## First-boot automation (setup Jobs)

Some services require out-of-band initialisation after their first deploy (admin
user creation, API key generation, service wiring). These are implemented as
Helm post-install/post-upgrade hook Jobs so they run automatically on every
`make deploy` and are idempotent.

| Job | Hook weight | What it does |
|-----|-------------|--------------|
| `jellyfin-setup` | 10 | Completes the startup wizard, creates the `admin` user, generates a Homepage API key, writes it to the `jellyfin-apikey` Secret, restarts Homepage. On re-runs: verifies credentials and ensures the Secret exists. |
| `jellyseerr-setup` | 20 | Connects Jellyseerr to Jellyfin (sets `ip`, `port`, external hostname). Handles both first-boot (full init via `POST /auth/jellyfin`) and re-runs (re-login without hostname). |

Both jobs run in the `media` module. `jellyseerr-setup` has a higher weight so
it always runs after `jellyfin-setup`.

**Homepage API key injection.**  
The Jellyfin API key is stored in the `jellyfin-apikey` Secret
(`HOMEPAGE_VAR_JELLYFIN_API_KEY`). Homepage mounts it via `envFrom` with
`optional: true` (so it starts before the Job has run). The ConfigMap references
it as the literal string `{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}`, which Homepage
substitutes at runtime. The setup Job patches the Homepage Deployment to trigger
a rollout after writing the Secret.

**Seeding config files on first boot.**  
Services whose images rewrite their config on startup (e.g. Bazarr, Jellyfin,
Transmission) use an init container to seed the config from a ConfigMap only
when no file already exists, preserving runtime changes on pod restarts:
```yaml
initContainers:
- name: seed-config
  image: busybox:1
  command: ["sh", "-c", "[ ! -f /config/config.yaml ] && cp /seed/config.yaml /config/config.yaml || true"]
```
Transmission is an exception: its linuxserver init script always overwrites
settings — see the postStart hook pitfall above.

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
3. Reference as `ghcr.io/platypod/<name>:<tag>` in the values file.

---

## Environment variable

`PLATYPOD__HELM__DEFAULT_ENV=dev` — used by `bin/helm.sh` functions as the default env
when `--env` is not passed. The Makefile uses `ENV=dev` instead and passes it directly
to helmfile; this variable is only relevant if you source `bin/helm.sh` directly.
