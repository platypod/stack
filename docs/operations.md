# Operations

Running the stack day to day. For chart structure and conventions see
[conventions.md](conventions.md); for the command reference see
[make-targets.md](make-targets.md); for how the Git+Flux model itself works
see [flux-migration.md](flux-migration.md).

**Deployment is Git-driven.** Every push to `main` reconciles onto `local`
within its poll interval (or immediately via `flux reconcile`); `prd` only
moves when a new `vX.Y.Z` tag is pushed (lockstep in `stack` and
`platypod-sops`). There is no `make deploy` — see the day-to-day section
below for the `flux`/`kubectl` equivalents.

## Local lifecycle (first time)

Prerequisites: a running local cluster (`make apply ENV=local` in [`../../infra`](../../infra/README.md)).
The Makefile auto-discovers the kubeconfig under the infra `.generated/local/`.

```sh
make install-deps    # helm, kubectl, flux, sops, age
make setup-local     # one-time per machine — see below
```

`make setup-local` runs, in order:

1. **`setup-age-key`** — restores the SOPS age key from the NFS backup (or
   generates + backs up a fresh one on a genuinely first-ever setup).
2. **`setup-local-tls`** — installs mkcert, trusts the local CA in the macOS
   Keychain (sudo prompt), generates a `*.platypod.local` cert, stores it as the
   `platypod-local-tls` secret.
3. **`install-crds`** — applies the vendored Traefik CRDs (IngressRoute, Middleware).
4. **`flux-bootstrap`** — bootstraps Flux against `clusters/local` (adds a
   read-only deploy key to `platypod/stack`, pushes `flux-system` manifests).
   Idempotent — safe to re-run.
5. **`flux-sops-secrets`** — adds the read-only deploy key + `sops-age` Secret
   `platypod-sops`'s `GitRepository`/`Kustomization` need to decrypt
   `clusters/local/secrets.enc.yaml`.
6. Forces a reconcile of the `apps` Kustomization — this is what actually
   brings up all 8 modules (persistence → core → security → …, ordered by
   each `HelmRelease`'s `dependsOn`), rather than waiting out Flux's own
   poll interval.
7. **`setup-local-dns`** — points system DNS at AdGuard's LoadBalancer IP
   (`192.168.122.201`, now up from step 6) with `1.1.1.1` fallback (sudo
   prompt). AdGuard rewrites `*.platypod.local → 192.168.122.200` (Traefik)
   internally. When the cluster is suspended, internet DNS falls through to
   `1.1.1.1`; `*.platypod.local` simply won't resolve.

> Verified 2026-08-24 by re-running every step live against the already-
> bootstrapped `local` cluster (each one is idempotent, so this is a real
> test even without a from-scratch rebuild): age key, TLS, CRDs, Flux
> bootstrap, `flux-sops-secrets`, and the `apps` reconcile all completed
> cleanly, all 8 `HelmRelease`s stayed healthy throughout. **Not** verified
> from a genuinely empty cluster (destroy + apply) — the one real rebuild
> this migration did (Phase 3) predates Phase 8's chain changes. `setup-
> local-dns`'s interactive `sudo` prompt also still hasn't actually been run
> on this machine (confirmed via `scutil --dns` — DNS is still on the
> router default, not AdGuard) — a real, standing gap since Phase 3, not
> new. Run it yourself: `make setup-local-dns`.

Local's worker node can't run every service at once — most services outside
`persistence`/`core`/`security` (the always-on base) are `enable: false` by
default in `platypod-sops`'s `clusters/local/secrets.enc.yaml`. Flip one to
`true` there and push to bring it up; no separate module-level gate exists
anymore (Phase 4 ported all 8 modules' `HelmRelease`s at once — see
[flux-migration.md](flux-migration.md)).

### Day-to-day

```sh
make status                                          # list deployed releases (ENV=local|prd)
flux get helmreleases -n local-platypod               # per-release health
flux reconcile helmrelease core -n local-platypod     # force one release to pick up a change now
flux reconcile kustomization apps -n flux-system      # force the whole apps tree
flux logs -n local-platypod                           # tail Flux's own reconcile logs
```

There is no `make diff`/`make deploy`/`make destroy` anymore — see
[flux-migration.md](flux-migration.md) for why (Git + Flux own the release
lifecycle) and for `postBuild.substitute`'s scan-the-whole-manifest
gotcha (12) if a change to `apps/base/` breaks reconciliation everywhere at
once. To preview a chart change before pushing, `helm template`/`helm diff`
the chart directly against the rendered `apps/base/` output
(`kubectl kustomize apps/base`), or push to a throwaway branch and point a
scratch `GitRepository` at it.

### After a cluster restart

kubeconfig and the TLS secret survive cluster reboots (the secret lives in etcd);
the DNS change is permanent. Nothing to redo — unless the cluster was rebuilt from
scratch (`make destroy` + `make apply` in infra), in which case re-run `make setup-local`.

### Accessing persistent-volume data (local)

Talos has no SSH, so use `talosctl` to browse/transfer files on the worker:

```sh
export TALOSCONFIG=../infra/.generated/local/talosconfig
talosctl -n 192.168.122.102 ls   /var/local/platypod/volumes/apps/
talosctl -n 192.168.122.102 read /var/local/platypod/volumes/apps/<file>
talosctl -n 192.168.122.102 cp   /var/local/platypod/volumes/apps/<file> ./<file>
talosctl -n 192.168.122.102 cp   ./<file> /var/local/platypod/volumes/apps/<file>
```

## Prod lifecycle

Prod is fully cut over onto Flux (Phase 7) — `clusters/prd/`'s
`GitRepository`s track `semver: ">=1.0.0"` in both `stack` and
`platypod-sops`, not `branch: main`. A prod deploy is:

```sh
git tag vX.Y.Z && git push --tags   # in stack, and in platypod-sops if it also changed
```

Both repos, lockstep, even for a change that only touches one — see
[flux-migration.md](flux-migration.md)'s "prod pinned to a tag" decision.
Rollback is re-tagging a previous good commit at a new, higher version (Flux
resolves the *highest* matching tag — you can't "go back" to an old tag
without a new one, since `>=1.0.0` always prefers the latest that satisfies
it).

```sh
flux get helmreleases -n prd-platypod     # per-release health
flux get sources git -n flux-system       # confirm both repos resolved the tag, not main
```

Prod stores PV data on the **Synology NFS** (`192.168.1.30:/volume1/kubernetes`).
The PVs use the `nfs.csi.k8s.io` driver, Flux-managed via
`infrastructure/csi/` (prod-only — local uses its own hostPath and doesn't
need it). There is no `make install-csi` — running one imperatively again
would fight the Flux-managed release for ownership (see
[flux-migration.md](flux-migration.md) gotcha 14).

> **Synology export ACL.** Talos VM traffic is NAT-masqueraded to each host's LAN
> IP (see infra `host-nat.sh`), so the NAS sees mounts from the *host* IPs, not the
> `10.0.x.x` VM IPs. The `/volume1/kubernetes` export must allow both worker hosts:
> `192.168.1.60` (mini1/w2) and `192.168.1.61` (mini4/w1).

Prod uses public DNS (`platypod.ovh`) and ACME/Let's Encrypt for TLS — no mkcert.
The ACME email/endpoint, and every other prod-specific override, live in
`platypod-sops/clusters/prd/secrets.enc.yaml` now (migrated from the old
NFS-symlinked `values/prd/values.yaml` in Phase 7) — `sops -d` it to read,
same as `local`'s.

> Prod's control plane is bare metal on the LAN (`chuwi-cp1`,
> `https://k8s.platypod.lan:6443`), directly reachable — the Makefile points
> `ENV=prd` at `../infra/.generated/prod/kubeconfig`, no tunnel needed. Before
> the 2026-07-30 cutover the control plane was a vfkit guest reachable only via
> SSH tunnel; see `../infra/docs/baremetal-cp-migration.md`.

> **DNS.** `make setup-prod-dns` points this laptop's system DNS at prod's
> AdGuard (`192.168.1.156`), same mechanism as `setup-local-dns`. AdGuard also
> serves the `k8s.platypod.lan → 192.168.1.156` rewrite
> (`adguard.rewrites` in prod's secrets), but keep a manual
> `/etc/hosts` line for that name too — if AdGuard's pod is ever down, that's
> the only way kubectl still resolves the API to fix it. See
> `../infra/docs/decisions.md`.

## Local vs prod

| Concern | local | prod |
|---------|-----|------|
| Namespace | `local-platypod` | `prd-platypod` |
| Domain | `platypod.local` | `platypod.ovh` |
| TLS | self-signed wildcard (mkcert) + `TLSStore default` | ACME (Let's Encrypt prod) |
| `certResolver` in IngressRoutes | omitted | `letsencrypt` |
| Storage | local hostPath (`/var/local/platypod/volumes/`) | Synology NFS (`192.168.1.30`) |
| PV node affinity | label `platypod.io/local-storage=true` | n/a (NFS is cluster-wide) |
| DNS | AdGuard + system resolver | public DNS |
| `GitRepository.spec.ref` | `branch: main` (reconciles HEAD) | `semver: ">=1.0.0"` (tag-gated) |
