# stack (services) — context for Claude

The Kubernetes workload stack: each module is a Helm chart, deployed via Flux
(Git-driven — see [docs/flux-migration.md](docs/flux-migration.md)) onto the
cluster from [`../infra`](../infra/README.md). local (the laptop's own
cluster, renamed from "dev" 2026-08-24) = `platypod.local`, prod = `platypod.ovh`.

**Start with [README.md](README.md)** for the overview and module list. Details
live in `docs/` and in each module's `src/<module>/README.md`:

- [docs/branching.md](docs/branching.md) — **which branch deploys where**, promoting to prod
- [docs/operations.md](docs/operations.md) — local/prod lifecycle, day-to-day, local-vs-prod, PV access
- [docs/make-targets.md](docs/make-targets.md) — every `make` target + variables
- [docs/conventions.md](docs/conventions.md) — chart structure, value conventions, pitfalls, setup Jobs, adding a service/image
- [docs/services.md](docs/services.md) — service catalog by module
- [docs/authentication.md](docs/authentication.md) — Authelia forward-auth + OIDC
- [docs/TODO.md](docs/TODO.md) — backlog
- `src/<module>/README.md` — per-module deep-dives

## Where to look (read the one file, not all of `docs/`)

| If the talk is about… | Start here |
|---|---|
| Adding/editing a service, chart structure, value conventions, setup Jobs, pitfalls | [docs/conventions.md](docs/conventions.md) |
| Which service is in which module / the catalog | [docs/services.md](docs/services.md) |
| Deep-dive on one service | `docs/<module>/<service>.md` (e.g. [docs/media/jellyfin.md](docs/media/jellyfin.md), [docs/security/authelia.md](docs/security/authelia.md)) |
| Auth: Authelia forward-auth, OIDC, LLDAP seeding | [docs/authentication.md](docs/authentication.md) + [docs/security/](docs/security/README.md) |
| Which branch deploys where, promoting to prod, image automation | [docs/branching.md](docs/branching.md) |
| Deploy/lifecycle, local-vs-prod, PV access, day-to-day | [docs/operations.md](docs/operations.md) |
| `make` targets + variables | [docs/make-targets.md](docs/make-targets.md) |
| Backlog | [docs/TODO.md](docs/TODO.md) |

Modules: `core` `dev-tools` `files` `games` `media` `observability` `persistence`
`security` — each has `src/<module>/README.md` and `docs/<module>/`.

## Critical rules (full rationale in the linked docs)

- **Always wrap template-valued strings with `tpl`** — `{{ tpl .Values.x.host . }}`,
  not `{{ .Values.x.host }}`. Silent at template time, broken at runtime.
- **NEVER set pod-level `fsGroup` on pods mounting the NFS PVCs** — it recursively
  chowns the whole 18 TB share and wedges the node. Use `runAsUser`/`runAsGroup`
  + an init container that chowns only the service's own subPath.
- Pods mounting a ConfigMap need a `checksum/config` annotation to auto-restart.
- Helm parses `{{ }}` in YAML comments too — escape or avoid them.
- **Deploy is Git + Flux, not `make`** — **`dev` deploys local, `main` deploys
  prod, and merging `dev` into `main` IS the prod deploy.** No tag is involved;
  the old lockstep-tag gate is retired. Never push straight to `main` unless you
  mean "deploy to prod, now". Image automation (including prod's own) writes
  only to `dev` — see [docs/branching.md](docs/branching.md), which is
  authoritative over any comment inside a `gotk-sync.yaml`, because
  `flux bootstrap` silently strips those. Each module's
  `HelmRelease.spec.dependsOn` (`apps/base/helmrelease-*.yaml`) enforces the
  same order Helmfile's `needs:` graph used to — `files` needs `media` — but
  now it's enforced by helm-controller itself, so `flux reconcile helmrelease
  files` alone can't bypass it the way `helmfile --selector` used to.
- **prod has no MetalLB.** Traefik and AdGuard reach the LAN via Service
  `externalIPs` on the bare-metal node (`traefik.externalIP` /
  `adguard.externalIP`), not `hostNetwork` — PodSecurity `baseline` forbids host
  namespaces and host ports, and `prd-platypod` stays at baseline. local is
  unchanged and still uses MetalLB.
- **Every image is pinned**; no `:latest`. Pins were taken from the digests
  running on 2026-07-30 and verified to resolve back to the same digest.

See [docs/conventions.md](docs/conventions.md) for the rest.
