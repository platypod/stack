# uptime-kuma (observability)

Black-box uptime monitoring, with its own admin login (`dev_user`).

- **Image:** `louislam/uptime-kuma:1.23.17` — **pinned to the 1.23.x stable line.**
  2.x is a beta that **dropped the Socket.io API** the seed Job relies on; do not bump.
- **Storage:** SQLite on the **local `config` volume** (not NFS — WAL). See
  [[sqlite-on-nfs-localconfig]].
- **Monitors:** seeded by the [setup job](uptime-kuma-setup-job.md); they are
  **in-cluster** HTTP checks (ClusterIP, not the public URL) so they bypass Authelia
  and report real app health instead of a 302 to the login page.

Related: [[uptime-kuma-version-pin]].
