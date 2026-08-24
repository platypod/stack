# persistence module

Storage primitives for the whole stack — PVs/PVCs and the SQLite-config backup.
Ships no user-facing service; everything else mounts what this defines.

## Volumes
- **`media` / `apps`** — the large data volumes. On prod they are **NFS** (Synology,
  `nfs.csi.k8s.io`, `nfsvers=4.1`, reclaim `Retain`); on dev they are local
  hostPath-style `localStorage`. `localStorage` and `nfs` are mutually exclusive
  (a `fail` guard enforces it).
- **`config`** — dedicated **local (non-NFS)** volume for SQLite app config dirs.
  Defaults to `apps` (dev), overridden to the local `config` volume on prod via
  `storage.localConfig.enable`. **Why:** SQLite WAL mode can't run over NFS (the
  `-shm` shared-memory file is unsupported) → lag/locks/crashes. Unlike
  `localStorage`, `localConfig` is designed to **coexist** with NFS, so it has its
  own flag and is exempt from the localStorage/nfs either-or guard. Pinned to
  nodes via the `platypod.io/local-storage` nodeAffinity label.

See [conventions.md](../conventions.md) for the failure mode that motivated this.

## Jobs
- [config-backup-cronjob](config-backup-cronjob.md) — nightly backup of the local
  config volume to NFS.
