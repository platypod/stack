# persistence module

Provides the two shared PVCs every other module mounts: **`apps`** (config /
state) and **`media`** (the large media library). No public ingress.

The backend is **environment-switched** via mutually-exclusive flags in
`storage.<backend>.enable`:

| | dev | prod |
|--|-----|------|
| Backend | `localStorage` (hostPath) | `nfs` (Synology) |
| Location | `./volumes/` on the labelled worker | `192.168.1.30` shares `media` + `apps` |
| Reclaim | — | **Retain** |

## local-storage (dev)

hostPath PVs pinned to the worker carrying the `platypod.io/local-storage=true`
node label (via `nodeAffinity`). A dedicated `storage-class` plus static PV/PVC
pairs bind by `volumeSelector` label.

## nfs (prod)

Static NFS PVs/PVCs pointing at the Synology shares, `reclaimPolicy: Retain`.

> **The prod NFS shares hold the only copy of the data — no backup or snapshot
> exists.** Never delete anything from `192.168.1.30:/volume1/kubernetes`
> (`media` + `apps`) without explicit consent. Consumers must **never** set
> `fsGroup` on these PVCs (recursive chown of the whole share) — chown only the
> app's own subdirectory via an initContainer. See CLAUDE.md.
