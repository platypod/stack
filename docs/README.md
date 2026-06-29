# platypod — stack documentation

Documentation for the **service stack** (the workloads deployed onto the cluster).
For cluster provisioning see [`infra/k8s-in-vms`](../../infra/CLAUDE.md).

| Doc | Contents |
|-----|----------|
| [operations.md](operations.md) | Running it: dev/prod lifecycle, day-to-day, dev-vs-prod, PV access |
| [make-targets.md](make-targets.md) | Every `make` target + variables |
| [conventions.md](conventions.md) | Chart structure, value conventions, pitfalls, setup Jobs, adding a service |
| [services.md](services.md) | Catalog of every service, by module, with its auth model |
| [authentication.md](authentication.md) | Authelia forward-auth + OIDC, who uses what, access groups |
| [decisions.md](decisions.md) | Non-obvious *why-we-built-it-this-way* choices for the stack |
| [TODO.md](TODO.md) | Consolidated backlog (soon / later / done) |

Per-module deep-dives live in each module's `README.md`:
[core](../src/core/README.md) ·
[security](../src/security/README.md) ·
[dev-tools](../src/dev-tools/README.md) ·
[media](../src/media/README.md) ·
[files](../src/files/README.md) ·
[games](../src/games/README.md) ·
[observability](../src/observability/README.md) ·
[persistence](../src/persistence/README.md)

**Per-service/job reference** — one page per workload (role + non-default config +
quirks) under `docs/<module>/`:
[persistence](persistence/README.md) ·
[core](core/README.md) ·
[security](security/README.md) ·
[observability](observability/README.md) ·
[files](files/README.md) ·
[games](games/README.md) ·
[media](media/README.md) ·
[dev-tools](dev-tools/README.md)

The operational reference (chart structure, value conventions, dev/prod
differences, how to add a service) is split across
[operations.md](operations.md) and [conventions.md](conventions.md).
