# Conventions & development

How the stack is structured and the non-obvious rules for working on it. For the
service catalog see [services.md](services.md); for auth see
[authentication.md](authentication.md); per-service detail lives in each module's
`src/<module>/README.md`.

## Structure

```
src/<module>/            # Helm chart per module (Chart.yaml committed)
  templates/<service>/   # K8s manifests (Deployment, Service, IngressRoute, …)
  README.md              # Per-module deep-dive
apps/base/
  values/<module>.yaml   # Default values — one file per module (substrate/
                          # registry/7 module files), env-agnostic. The one
                          # source of truth (see flux-migration.md gotcha 15
                          # for why there used to be a second, drifting copy)
  helmrelease-<module>.yaml  # Flux HelmRelease per module, shared across
                          # clusters — ${env} tokens resolved per cluster
                          # (see clusters/<env>/apps.yaml)
clusters/<env>/           # Per-cluster Flux wiring: apps.yaml, secrets.yaml,
                          # infrastructure.yaml, flux-system/ (bootstrap-generated)
Makefile                 # Cluster bootstrap + one-time setup (see make-targets.md)
```

Env-specific secrets/overrides live in the separate `platypod-sops` repo
(`clusters/<env>/secrets.enc.yaml`, SOPS-encrypted), not in this repo — see
[flux-migration.md](flux-migration.md)'s SOPS design.

Modules: `persistence`, `core`, `security`, `observability`, `dev-tools`,
`files`, `media`, `games`. See [services.md](services.md) for the full per-module
service list.

## Key conventions

- Services are exposed via Traefik **`IngressRoute` CRDs** (not standard `Ingress`).
- SSO is an Authelia **`Middleware`** referenced from each IngressRoute.
- Values use Go template cross-references (`{{ .Values.some.key }}`),
  resolved by Helm at render time — same syntax throughout, no separate
  pre-processing step.
- Every `HelmRelease` gets all 9 default-value ConfigMaps (substrate,
  registry, all 7 module files) via `valuesFrom`, not just its own module's —
  cross-module references are real (e.g. Traefik reads `jellyfin.proxy.enable`
  from the `media` module). See [flux-migration.md](flux-migration.md) gotcha 2.
- Module release order is declared via each `HelmRelease`'s `spec.dependsOn`
  in `apps/base/helmrelease-*.yaml`.

## Pitfalls

**Always wrap template-valued strings with `tpl`.** If a value itself contains a
template (e.g. `host: "{{ .Values.foo.label }}.{{ .Values.traefik.domain }}"`),
referencing it as `{{ .Values.foo.host }}` renders the literal string — use
`{{ tpl .Values.foo.host . }}`. Omitting `tpl` is silent at `helm template` time
but broken at runtime.

**Helm SSA rejects `tls: {}` on Traefik IngressRoute CRDs.** When
`traefik.tls.selfSigned=true`, IngressRoutes must NOT use empty `tls: {}` (SSA
serialises it as JSON null, which the CRD rejects). Use `tls.store.name: default`.

**Pods mounting a ConfigMap need a checksum annotation to auto-restart.**
Kubernetes doesn't restart pods when a mounted ConfigMap changes. Add:
```yaml
template:
  metadata:
    annotations:
      checksum/config: {{ include (print $.Template.BasePath "/<config-map>.yaml") . | sha256sum }}
```

**Helm parses `{{ }}` everywhere — including YAML comments.** A comment like
`# ref {{MY_VAR}}` fails to parse. Escape as `{{ "{{MY_VAR}}" }}` or avoid braces
in comments.

**SQLite app config goes on the local `config` volume, NOT NFS.** SQLite WAL is
unsupported over NFS (the `-shm` mmap can't work), causing lag, "database is
locked" → 404s/popups, and crashes. On prod, app config DBs live on a dedicated
local hostPath volume (`storage.localConfig`, pinned to the local-storage node),
backed up nightly to NFS by the `config-backup` CronJob. Point a SQLite app's
config PVC at `{{ .Values.storage.defaultVolumes.config }}` (resolves to the local
`config` volume on prod, `dev-apps` on dev). Apps on an external DB (the *arrs use
Postgres `transverse-db`) don't need this. See [services.md](services.md) and the
[`sqlite-on-nfs`](operations.md) note.

**NEVER set pod-level `fsGroup` on pods mounting the NFS PVCs.** csi-driver-nfs
uses `fsGroupPolicy: File`, so the kubelet recursively chowns the ENTIRE share on
every pod start — on the 18 TB media volume this wedges the kubelet for hours,
knocks sibling pods to `Unknown` (502s elsewhere), and rewrites ownership on the
NAS. Use `runAsUser`/`runAsGroup` + an init container that chowns ONLY the
service's own subPath dir (see jellyseerr/kavita).

**The linuxserver Transmission image overwrites RPC whitelist on every start.**
It hardcodes `rpc-whitelist: "127.0.0.1,::1"` / empty `rpc-host-whitelist`,
blocking other pods and Traefik. Fix: a `lifecycle.postStart` hook that calls the
RPC from `localhost` to disable both checks (see
`src/files/templates/transmission/transmission--deployment.yaml`).

**A namespace env var doesn't always mean namespace-scoped RBAC.** `mc-router`
(games/Minecraft) sets `KUBE_NAMESPACE` and its own docs say that restricts its
Service watch to one namespace — in practice (confirmed live, v1.23.0) its
informer still issues a cluster-scope `List`/`Watch` on Services regardless,
so a namespaced `Role`/`RoleBinding` fails with `services is forbidden ... at
the cluster scope`. Needed a `ClusterRole`/`ClusterRoleBinding` instead
(read-only on Services, cluster-wide) — matches upstream's own example
manifests, which use `ClusterRole` too. Don't trust a tool's "just set this
namespace env var" claim for RBAC scoping without a live check.

**LLDAP doesn't update the admin password on restart.** `LLDAP_LDAP_USER_PASS`
only applies on first creation (fresh DB). To change it on a running instance:
```sh
kubectl -n <ns> run -it --rm pw --image=lldap/lldap:stable --restart=Never \
  --command -- /app/lldap_set_password --base-url http://lldap:<port> \
  --admin-username admin --admin-password <current> --username admin --password <new>
```
Keep `lldap.adminPassword` in values in sync with the actual DB password.

## First-boot automation (setup Jobs)

Services needing out-of-band init (admin creation, API keys, wiring) use Helm
post-install/post-upgrade **hook Jobs** — they run on every Helm upgrade
(including Flux-triggered ones) and are idempotent (exit 0 on partial so the
release still succeeds). Gate any *arr-app polling in these Jobs on that
app's own `.enable` flag, not unconditionally — an app that's legitimately
disabled (e.g. on `local`'s undersized node) has no Service to resolve, and
an ungated wait loop hangs for its full timeout instead of skipping (see
[flux-migration.md](flux-migration.md) gotcha 11). Examples:
`jellyfin-setup` (w10), `kavita-setup` (w15), `audiobookshelf-setup` (w17),
`jellyseerr-setup` (w20), `reclaimerr-setup` (w30), `suwayomi-setup` (w25),
`uptime-kuma-setup` (w20). Hook weights order dependent jobs.

**Homepage API key injection.** The Jellyfin API key lives in the
`jellyfin-apikey` Secret (`HOMEPAGE_VAR_JELLYFIN_API_KEY`); Homepage mounts it via
`envFrom` with `optional: true` and references it as the literal
`{{HOMEPAGE_VAR_JELLYFIN_API_KEY}}`. The setup Job writes the Secret and patches
the Homepage Deployment to roll out.

**Seeding config on first boot.** Services whose images rewrite their config on
start (Bazarr, Jellyfin) use an init container that copies a seed file only if
none exists, preserving runtime changes:
```yaml
initContainers:
- name: seed-config
  image: busybox:1
  command: ["sh", "-c", "[ ! -f /config/config.yaml ] && cp /seed/config.yaml /config/config.yaml || true"]
```

## Adding a new service

1. Create `src/<module>/templates/<service>/` with the K8s manifests.
2. Add the service's values (image, resources, ports, config) to
   `apps/base/values/<module>.yaml` under its own top-level key (use
   `{{ .Values.x.y }}` to cross-reference other keys, same as any other
   value). If it's Traefik-routed, also add its `enable`/`label`/`host`
   triple to `apps/base/values/registry.yaml`.
3. Override per-environment in `platypod-sops`'s
   `clusters/<env>/secrets.enc.yaml` as needed (`sops -d`/`sops -e`
   round-trip — see [flux-migration.md](flux-migration.md)).
4. Pattern: Deployment → Service → IngressRoute (+ Authelia middleware if auth'd).
