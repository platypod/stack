# Operations

Running the stack day to day. For chart structure and conventions see
[conventions.md](conventions.md); for the command reference see
[make-targets.md](make-targets.md).

## Local lifecycle (first time)

Prerequisites: a running local cluster (`make apply ENV=local` in [`../../infra`](../../infra/README.md)).
The Makefile auto-discovers the kubeconfig under the infra `.generated/local/`.

```sh
make install-deps    # helm, helmfile, kubectl, helm-diff
make setup-local     # one-time per machine — see below
make deploy          # full stack
```

`make setup-local` runs, in order:

1. **`setup-local-tls`** — installs mkcert, trusts the local CA in the macOS
   Keychain (sudo prompt), generates a `*.platypod.local` cert, stores it as the
   `platypod-local-tls` secret.
2. **`install-crds`** — applies the Traefik CRDs (IngressRoute, Middleware).
3. **`deploy MODULE=core`** — Traefik (gets a `192.168.122.200+` MetalLB IP) + Homepage.
4. **`setup-local-dns`** — points system DNS at AdGuard's LoadBalancer IP
   (`192.168.122.201`) with `1.1.1.1` fallback. AdGuard rewrites
   `*.platypod.local → 192.168.122.200` (Traefik) internally. When the cluster is
   suspended, internet DNS falls through to `1.1.1.1`; `*.platypod.local` simply
   won't resolve.

After `setup-local` the base stack (persistence + core + security) is running.
Add modules individually — the 4 GB local worker can't run everything at once:

```sh
make deploy MODULE=observability   # dashboards
make deploy MODULE=media           # Jellyfin/Sonarr/etc.
```

### Day-to-day

```sh
make deploy                  # sync full stack
make deploy MODULE=core      # sync one module
make destroy MODULE=core     # uninstall one module
make diff MODULE=core        # dry-run diff
make status                  # list deployed releases
```

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

```sh
make install-deps
make install-crds ENV=prd
make install-csi  ENV=prd   # NFS CSI driver — required for NFS-backed prod PVs
make deploy ENV=prd
```

Prod stores PV data on the **Synology NFS** (`192.168.1.30:/volume1/kubernetes`).
The PVs use the `nfs.csi.k8s.io` driver, which is **not** built into Talos —
`make install-csi` deploys it (pinned via `CSI_DRIVER_NFS_VERSION`). Local uses
its own hostPath and doesn't need it.

> **Synology export ACL.** Talos VM traffic is NAT-masqueraded to each host's LAN
> IP (see infra `host-nat.sh`), so the NAS sees mounts from the *host* IPs, not the
> `10.0.x.x` VM IPs. The `/volume1/kubernetes` export must allow both worker hosts:
> `192.168.1.60` (mini1/w2) and `192.168.1.61` (mini4/w1).

Prod uses public DNS (`platypod.ovh`) and ACME/Let's Encrypt for TLS — no mkcert.
The ACME email/endpoint are in `values/prd/values.yaml`.

> Prod's control plane is bare metal on the LAN (`chuwi-cp1`,
> `https://k8s.platypod.lan:6443`), directly reachable — the Makefile points
> `ENV=prd` at `../infra/.generated/prod/kubeconfig`, no tunnel needed. Before
> the 2026-07-30 cutover the control plane was a vfkit guest reachable only via
> SSH tunnel; see `../infra/docs/baremetal-cp-migration.md`.

> **DNS.** `make setup-prod-dns` points this laptop's system DNS at prod's
> AdGuard (`192.168.1.156`), same mechanism as `setup-local-dns`. AdGuard also
> serves the `k8s.platypod.lan → 192.168.1.156` rewrite
> (`adguard.rewrites` in `values/prd/values.yaml`), but keep a manual
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
