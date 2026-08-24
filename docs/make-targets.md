# Make targets (stack)

The `Makefile` is the primary interface to the service stack (Helmfile under the
hood). `make help` prints this list live. Default goal is `help`.

## Common variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `ENV` | `local` | Environment — `local` or `prd`. Selects the namespace, value overlays, and kubeconfig |
| `MODULE` | *(all)* | Limit a deploy/diff/destroy to one module (e.g. `core`, `media`) |
| `KUBECONFIG` | auto | Resolved from the infra `.generated/<env>/` kubeconfig; override on the command line if needed |
| `TRAEFIK_VERSION` | `v3.5` | Traefik CRD version for `install-crds` |
| `CSI_DRIVER_NFS_VERSION` | `4.13.2` | NFS CSI driver chart version for `install-csi` |
| `IMAGE`, `VERSION` | — | For `build` (custom image name + tag) |

> `ENV` uses `local`/`prd`, but the infra writes kubeconfigs under `local`/`prod` —
> the Makefile maps `prd` to `.../prod/kubeconfig` automatically. Prod's control
> plane is bare metal on the LAN, directly reachable — no tunnel involved.

## Dependencies

| Target | What it does |
|--------|--------------|
| `make install-deps` | Install required tools (helm, helmfile, kubectl, helm-diff) |
| `make check-deps` | Report which tools are installed without installing |

## Local setup (macOS, one-time)

| Target | What it does |
|--------|--------------|
| `make setup-local-tls` | Trust the mkcert CA + create/refresh the wildcard TLS secret in the cluster |
| `make setup-local-dns` | Point system DNS at AdGuard (primary) + `1.1.1.1` (fallback); clean up dnsmasq |
| `make setup-prod-dns` | Same, for prod's AdGuard (`192.168.1.156`) — also serves the `k8s.platypod.lan` rewrite. Keep a manual `/etc/hosts` line for that name too; see `../infra/docs/decisions.md` |
| `make setup-local` | Full local bootstrap: age key → TLS → CRDs → base deploy → DNS → Flux |

## Cluster bootstrap

| Target | What it does |
|--------|--------------|
| `make setup-age-key` | Restore the SOPS age key from the NFS backup, or generate + back up a fresh one (only when no backup exists) |
| `make vendor-crds` | Re-fetch the vendored Traefik CRDs from upstream (`TRAEFIK_VERSION=v3.5`) — run when bumping the version |
| `make install-crds` | Apply the vendored Traefik CRDs (IngressRoute, Middleware, …) to the cluster |
| `make install-csi` | Install the NFS CSI driver — required for NFS-backed **prod** storage |
| `make flux-bootstrap` | Bootstrap/reconcile Flux against `clusters/$(ENV)` — idempotent, safe to re-run (`ENV=local`) |

## Deployment

| Target | What it does |
|--------|--------------|
| `make status` | List deployed Helm releases for `ENV` |
| `make diff` | Dry-run: show what a deploy would change (`ENV=local MODULE=core`) |
| `make deploy-base` | Deploy the always-on base only: persistence, core, security |
| `make deploy` | Deploy the full stack, or one module with `MODULE=` |
| `make destroy` | Uninstall the full stack, or one module with `MODULE=` |

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
make setup-local                        # one-time local bootstrap
make deploy ENV=local MODULE=core         # redeploy just the core module on local
make deploy ENV=prd                     # deploy the full stack to prod
make diff ENV=prd MODULE=security       # preview a prod change
make build IMAGE=pokeclicker VERSION=v0.10.25
make deploy ENV=local MODULE=dev-tools    # redeploy dev-tools (Headroom currently disabled)
```
