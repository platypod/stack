# files module

Torrent clients writing into the NFS `media` share.

## Services
- [transmission](transmission.md) — Transmission + a Prometheus exporter sidecar.
- [qbittorrent](qbittorrent.md) — qBittorrent.
- [deluge](deluge.md) — Deluge.

**Convention note:** all three use **LinuxServer (`lscr.io`) images on `:latest`** —
unpinned, unlike the rest of the stack. Worth pinning during a maintenance pass.
Each exposes its WebUI host via Traefik plus BitTorrent peer ports (TCP/UDP nodePorts).
