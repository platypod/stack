# transmission (files)

Transmission BitTorrent client + a metrics exporter.

- **Image:** `lscr.io/linuxserver/transmission:latest` (**unpinned** — LinuxServer image).
- **Exporter sidecar:** `ghcr.io/platypod/transmission-exporter:0.3.0` (custom image,
  built to GHCR) on port `9092` — scraped by the collector's `transmission` Prometheus
  job, feeding the dashboards.
- **Ports:** WebUI `9091` (host via Traefik), peer `51413` (TCP/UDP nodePort).
- **Storage:** downloads land on the NFS `media` share.

The exporter is the only non-default bit; Transmission itself is stock LinuxServer
(PUID/PGID + `/config`).

## Operational rule: `downloads/transmission/finished` is copy-only

When reorganizing media libraries (books, manga, etc.) sourced from
`media/downloads/transmission/finished/` on the NFS share, **never `mv`/`rm`
anything inside that tree — only copy out of it** into the target library
folder. Transmission needs the original files to stay in place for seeding/
ratio tracking; moving or deleting them out from under it breaks that. Any
reorg script or manual step touching that path must use `cp`/`rsync` without
`--remove-source-files`. Files already inside a library folder (`books/`,
`audio-books/`, etc.) are not part of this rule and can be freely moved/renamed
during a reorg.
