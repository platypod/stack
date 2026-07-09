# media module

The media stack: acquisition (*arr), serving (Jellyfin/Komga/Kavita/Suwayomi),
requests (Jellyseerr), and housekeeping. Many apps use SQLite on the **local
`config` volume** (NFS can't host WAL — [[sqlite-on-nfs-localconfig]]).

## Services
| Service | Image | Notes |
|---|---|---|
| [jellyfin](jellyfin.md) | `jellyfin/jellyfin:latest` | media server; setup Job seeds it |
| [jellyseerr](jellyseerr.md) | `ghcr.io/seerr-team/seerr:v3.3.0` | requests; admin bit set via DB Job |
| [sonarr](arr-stack.md) | `linuxserver/sonarr:latest` | TV; Authelia **bypass** (own API) |
| [radarr](arr-stack.md) | `linuxserver/radarr:latest` | movies; Authelia bypass |
| [prowlarr](arr-stack.md) | `linuxserver/prowlarr:latest` | indexers; Authelia bypass |
| [readarr](arr-stack.md) | `ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.20.129` | books (Bookshelf fork — Readarr is EOL) |
| [bazarr](arr-stack.md) | `linuxserver/bazarr:latest` | subtitles; Authelia bypass |
| [flaresolverr](arr-stack.md) | `flaresolverr/flaresolverr:latest` | CF solver; Authelia bypass |
| [komga](komga.md) | `gotson/komga:1.25.0` | comics/manga (JVM) |
| [kavita](kavita.md) | `jvmilazz0/kavita:0.9.0.2` | ebooks; Authelia bypass; OIDC |
| [audiobookshelf](audiobookshelf.md) | `ghcr.io/advplyr/audiobookshelf:2.35.1` | audiobooks/podcasts; setup Job; OIDC |
| [suwayomi](suwayomi.md) | `ghcr.io/suwayomi/suwayomi-server:v2.2.2100` | manga; setup Job |
| [reclaimerr](reclaimerr.md) | `ghcr.io/jessielw/reclaimerr:latest` | disk reclaim; setup Job |
| [mediarvester](mediarvester.md) | `ghcr.io/platypod/mediarvester:v1.0.0` | **custom** image |
| [postgres](postgres.md) | `postgres:17` | DB for Jellyseerr |

## Jobs
[jellyfin-setup](jellyfin-setup-job.md), [jellyseerr-setup](jellyseerr-setup-job.md),
[kavita-setup](kavita-setup-job.md), [audiobookshelf-setup](audiobookshelf-setup-job.md),
[suwayomi-setup](suwayomi-setup-job.md), [reclaimerr-setup](reclaimerr-setup-job.md) —
post-install hooks (admin/config seeding).
