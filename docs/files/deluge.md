# deluge (files)

Deluge BitTorrent client.

- **Image:** `lscr.io/linuxserver/deluge:latest` (**unpinned**).
- **Ports:** WebUI `8112` (host via Traefik), peer `6881`/`6882`.
- **Storage:** downloads on the NFS `media` share.

Stock LinuxServer image (PUID/PGID + `/config`); nothing custom beyond exposure.
