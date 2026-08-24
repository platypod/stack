# config-backup (CronJob)

Nightly backup of the **local `config` volume** (the SQLite app DBs) to the NFS
`apps` share — durability for data that lives on fast local node disk because NFS
can't host SQLite WAL.

- **Template:** `src/persistence/templates/local-config/backup-cronjob.yaml`
- **Enabled:** only when `storage.localConfig.enable` (prod). Gated by
  `storage.localConfig.backup.enable` (default true).
- **Schedule:** `0 3 * * *` (03:00 daily) — `storage.localConfig.backup.schedule`.
- **Image:** `busybox:1` — just `tar`/`find`, no app runtime needed.
- **What it does:** tars the config volume into `config-<timestamp>.tgz` on the NFS
  apps share, then prunes archives older than **`retentionDays`** (default 14) via
  `find … -mtime +N -delete`.

**Rationale:** live SQLite is local (fast, WAL-safe); the backup lands on the
backed-up Synology, so a node loss doesn't lose app state. See
[conventions.md](../conventions.md).
