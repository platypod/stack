# kavita (media)

Ebook/digital library server.

- **Image:** `jvmilazz0/kavita:0.9.0.2` (pinned).
- **Auth:** on the Authelia **`bypass`** list (its own auth) and integrates OIDC.
- **Storage:** SQLite DB on the **local `config` volume** — critical: WAL on NFS caused
  lag/locks/crashes (see [conventions.md](../conventions.md)).
- **Status:** currently **disabled** (`enable: false`) — Kavita (.NET) SIGILL-crashes
  (exit 132) intermittently on the Apple Virtualization/Talos ARM guest.
  No container-level workaround eliminated it (W^X, HWIntrinsic, ReadyToRun,
  OpenSSL armcap all only reduced frequency). Reverted to
  [komga](komga.md) (JVM, unaffected). Kept configured (OIDC, local config
  volume) to revisit after a .NET version bump or a vfkit CPU-feature fix.
- **Setup:** [kavita-setup](kavita-setup-job.md).
