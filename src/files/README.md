# files module

Download clients: torrent (**Transmission**, **qBittorrent**, **Deluge**) and
usenet (**SABnzbd**).

All four are gated behind Authelia `download_user` and keep their own native
login. They write into the shared **media** NFS PVC so the *arrs can hardlink/move
completed downloads — same ownership rules as the media module apply (run as the
media user, **never** `fsGroup` on the NFS PVC).

- Transmission ships a **prometheus exporter** sidecar (`transmission-exporter`)
  for observability.
- Multiple torrent clients coexist so different *arrs / categories can target
  different download backends.
- SABnzbd's config/history db lives on the local `config` PVC (SQLite, not
  NFS-safe — see the SQLite pitfall in
  [docs/conventions.md](../../docs/conventions.md)), unlike the torrent
  clients which use the `apps` PVC.
- **SABnzbd is auto-wired on every deploy** by the `sabnzbd-setup` hook Job:
  it upserts itself as a Download Client into Sonarr/Radarr/Readarr, registers
  those three as Prowlarr Applications (so any indexer added to Prowlarr syncs
  to them automatically), and — if `prowlarr.indexers.althub.apiKey` is set —
  adds althub.co.za as a Newznab indexer. No manual UI wiring needed. See the
  Job's header comment for the full flow.
- **althub.co.za is a Newznab indexer, not a Usenet server** — SABnzbd still
  needs a separate NNTP block-account provider (`sabnzbd.provider.*` in
  values) before it can actually download anything. Open item — see
  [docs/TODO.md](../../docs/TODO.md).
