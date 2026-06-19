# stack (services) — context for Claude

The Kubernetes workload stack: each module is a Helm chart deployed via Helmfile
onto the cluster from [`../infra`](../infra/README.md). dev = `platypod.local`,
prod = `platypod.ovh`.

**Start with [README.md](README.md)** for the overview and module list. Details
live in `docs/` and in each module's `src/<module>/README.md`:

- [docs/operations.md](docs/operations.md) — dev/prod lifecycle, day-to-day, dev-vs-prod, PV access
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
| Deploy/lifecycle, dev-vs-prod, PV access, day-to-day | [docs/operations.md](docs/operations.md) |
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

See [docs/conventions.md](docs/conventions.md) for the rest.
