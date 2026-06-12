# files module

Torrent download clients: **Transmission**, **qBittorrent**, **Deluge**.

All three are gated behind Authelia `group:download` and keep their own native
login. They write into the shared **media** NFS PVC so the *arrs can hardlink/move
completed downloads — same ownership rules as the media module apply (run as the
media user, **never** `fsGroup` on the NFS PVC).

- Transmission ships a **prometheus exporter** sidecar (`transmission-exporter`)
  for observability.
- Multiple clients coexist so different *arrs / categories can target different
  download backends; usenet (SABnzbd/NZBGet) is a backlog item — see
  [docs/TODO.md](../../docs/TODO.md).
