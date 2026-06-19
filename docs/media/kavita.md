# kavita (media)

Ebook/digital library server.

- **Image:** `jvmilazz0/kavita:0.9.0.2` (pinned).
- **Auth:** on the Authelia **`bypass`** list (its own auth) and integrates OIDC.
- **Storage:** SQLite DB on the **local `config` volume** — critical: WAL on NFS caused
  lag/locks/crashes ([[sqlite-on-nfs-localconfig]]).
- **History:** Kavita (.NET) once **SIGILL-crashed on the ARM guest**, which drove a
  temporary switch to Komga; it's back on this pinned build. See
  [[kavita-sigill-use-komga]].
- **Setup:** [kavita-setup](kavita-setup-job.md).
