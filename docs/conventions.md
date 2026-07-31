# Conventions & development

How the stack is structured and the non-obvious rules for working on it. For the
service catalog see [services.md](services.md); for auth see
[authentication.md](authentication.md); per-service detail lives in each module's
`src/<module>/README.md`.

## Structure

```
src/<module>/           # Helm chart per module (Chart.yaml committed)
  templates/<service>/  # K8s manifests (Deployment, Service, IngressRoute, …)
  README.md             # Per-module deep-dive
values/
  default/<module>/     # Default values — .yaml.gotmpl (Go templates, env-agnostic)
  dev/values.yaml       # Dev overrides
  prd/values.yaml       # Prod overrides
helmfile.yaml.gotmpl    # Environments, value load order, release dependency graph
Makefile                # Primary interface (see make-targets.md)
```

Modules: `persistence`, `core`, `security`, `observability`, `dev-tools`,
`files`, `media`, `games`. See [services.md](services.md) for the full per-module
service list.

## Key conventions

- Services are exposed via Traefik **`IngressRoute` CRDs** (not standard `Ingress`).
- SSO is an Authelia **`Middleware`** referenced from each IngressRoute.
- Values use Go template cross-references (`{{ .Values.some.key }}`); the
  `.gotmpl` extension tells helmfile to render them before Helm sees them.
- Values load in dependency order in `helmfile.yaml.gotmpl` — foundational files
  first, cross-module aggregators (authelia) last, env override last of all.
- Module release order is declared via `needs:` in `helmfile.yaml.gotmpl`.

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
post-install/post-upgrade **hook Jobs** — they run on every `make deploy` and are
idempotent (exit 0 on partial so the release still succeeds). Examples:
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
2. Add `values/default/<module>/<service>.yaml.gotmpl` (use `{{ .Values.x.y }}`
   to cross-reference).
3. Add the file to the right position in `helmfile.yaml.gotmpl` (after anything it
   references, before authelia).
4. Override in `values/<env>/values.yaml` as needed.
5. Pattern: Deployment → Service → IngressRoute (+ Authelia middleware if auth'd).


## Environment variable

`PLATYPOD__HELM__DEFAULT_ENV=dev` — default env for `bin/helm.sh` functions when
`--env` isn't passed. The Makefile passes `ENV` to helmfile directly, so this only
matters if you source `bin/helm.sh` yourself.
