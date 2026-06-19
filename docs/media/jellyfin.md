# jellyfin (media)

The media server.

- **Image:** `jellyfin/jellyfin:latest` (**unpinned**).
- **Storage:** library on NFS `media`; config on the local `config` volume.
- **Metrics:** scraped via the json-exporter `jellyfin` module (playback) and/or the
  native Prometheus endpoint — both optional, gated in the collector values.
- **Setup:** [jellyfin-setup](jellyfin-setup-job.md) seeds initial config.
