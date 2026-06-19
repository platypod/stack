# qbittorrent (files)

qBittorrent BitTorrent client.

- **Image:** `linuxserver/qbittorrent:latest` (**unpinned**).
- **Ports:** WebUI `8080` (host via Traefik), peer `6881` (TCP/UDP).
- **Storage:** downloads on the NFS `media` share.

Stock LinuxServer image (PUID/PGID + `/config`); no custom config beyond the host
exposure and peer ports.
