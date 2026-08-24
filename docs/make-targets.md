# Make targets (stack)

The `Makefile` covers cluster bootstrap, one-time machine setup, and image
builds. `make help` prints this list live. Default goal is `help`.
**Deployment itself is Git + Flux, not `make`** — see
[operations.md](operations.md) and [flux-migration.md](flux-migration.md).

## Common variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `ENV` | `local` | Environment — `local` or `prd`. Selects the namespace and kubeconfig |
| `KUBECONFIG` | auto | Resolved from the infra `.generated/<env>/` kubeconfig; override on the command line if needed |
| `TRAEFIK_VERSION` | `v3.5` | Traefik CRD version for `vendor-crds`/`install-crds` |
| `CSI_DRIVER_NFS_VERSION` | `4.13.2` | NFS CSI driver chart version — informational only; the driver itself is Flux-managed (`infrastructure/csi/`), this just keeps the two in sync when bumping |
| `IMAGE`, `VERSION` | — | For `build` (custom image name + tag) |

> `ENV` uses `local`/`prd`, but the infra writes kubeconfigs under `local`/`prod` —
> the Makefile maps `prd` to `.../prod/kubeconfig` automatically. Prod's control
> plane is bare metal on the LAN, directly reachable — no tunnel involved.

## Dependencies

| Target | What it does |
|--------|--------------|
| `make install-deps` | Install required tools (helm, kubectl, flux, sops, age, …) |
| `make check-deps` | Report which tools are installed without installing |

## Local setup (macOS, one-time)

| Target | What it does |
|--------|--------------|
| `make setup-local-tls` | Trust the mkcert CA + create/refresh the wildcard TLS secret in the cluster |
| `make setup-local-dns` | Point system DNS at AdGuard (primary) + `1.1.1.1` (fallback); clean up dnsmasq |
| `make setup-prod-dns` | Same, for prod's AdGuard (`192.168.1.156`) — also serves the `k8s.platypod.lan` rewrite. Keep a manual `/etc/hosts` line for that name too; see `../infra/docs/decisions.md` |
| `make setup-local` | Full local bootstrap: age key → TLS → CRDs → Flux (brings up all 8 modules) → DNS. Hasn't been exercised end-to-end since Phase 8 (see `flux-migration.md`) — the one real rebuild this migration did predates it |

## Cluster bootstrap

| Target | What it does |
|--------|--------------|
| `make setup-age-key` | Restore the SOPS age key from the NFS backup, or generate + back up a fresh one (only when no backup exists) |
| `make vendor-crds` | Re-fetch the vendored Traefik CRDs from upstream (`TRAEFIK_VERSION=v3.5`) — run when bumping the version |
| `make install-crds` | Apply the vendored Traefik CRDs (IngressRoute, Middleware, …) imperatively — Flux applies the same vendored copy on its own via `infra-crds` |
| `make flux-bootstrap` | Bootstrap/reconcile Flux against `clusters/$(ENV)` — idempotent, safe to re-run (`ENV=local`\|`prd`) |
| `make flux-sops-secrets` | Create the in-cluster deploy key + `sops-age` Secret the `platypod-sops` `GitRepository` needs — idempotent, one-time per cluster (`ENV=local`\|`prd`) |

`csi-driver-nfs` (NFS CSI driver, prod-only) is Flux-managed —
`infrastructure/csi/`, wired in via `clusters/prd/infrastructure.yaml`. No
`make` target installs it imperatively anymore.

## Status

| Target | What it does |
|--------|--------------|
| `make status` | List deployed Helm releases and their status for `ENV` (`helm list`) |

For anything beyond a status check — diffing a pending change, forcing a
reconcile, checking why a release is stuck — use `flux`/`kubectl` directly.
See [operations.md](operations.md#day-to-day) for the common ones.

## Images

| Target | What it does |
|--------|--------------|
| `make build IMAGE=<name> VERSION=<tag>` | Build and push a custom image to `ghcr.io/platypod/<name>:<tag>` |

## Headroom proxy (dev-tools module) — **disabled**

[Headroom](https://github.com/headroomlabs-ai/headroom) is currently
**disabled** (`headroom.enable: false`) — see
[src/dev-tools/README.md](../src/dev-tools/README.md#headroom--disabled-cli-only-no-working-client-yet)
for why. Only the terminal `claude` CLI can ever be pointed at it;
**Claude Desktop hardcodes its own `ANTHROPIC_BASE_URL` and can't be
overridden** (verified — neither `settings.json` nor a session-wide
`launchctl setenv` reached it). These targets still work once the service is
re-enabled: they edit `~/.claude/settings.json`'s `env` block
(`bin/set-claude-proxy.sh`) — the same mechanism already used there for the
OTEL vars. A shell `export` alone doesn't work for the terminal CLI either
across restarts unless it's actually in that same shell — `settings.json` is
the durable, restart-proof way to set it.

| Target | What it does |
|--------|--------------|
| `make proxy-on` | Set `env.ANTHROPIC_BASE_URL = https://headroom.<domain>` in `~/.claude/settings.json`, for `ENV` |
| `make proxy-off` | Remove `env.ANTHROPIC_BASE_URL` from `~/.claude/settings.json` |

```bash
make proxy-on ENV=local   # then quit + relaunch the terminal `claude` CLI
make proxy-off          # then quit + relaunch again to stop routing through the proxy
```

settings.json is only read at process startup, so the change has no effect
until you restart — merely clearing/continuing a conversation in an
already-running process isn't enough.

## Examples

```bash
make setup-local                              # one-time local bootstrap
make status ENV=prd                           # list prod's Helm releases
make build IMAGE=pokeclicker VERSION=v0.10.25
```

Everything else — deploying a change, checking what a commit would do,
forcing a stuck release to retry — is Git + `flux`/`kubectl`, not `make`. See
[operations.md](operations.md).
