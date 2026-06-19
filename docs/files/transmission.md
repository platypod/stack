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
