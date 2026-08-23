# Service catalog

Every web-facing service in the stack, by module. Hostnames are
`<label>.<domain>` (`platypod.local` on dev, `platypod.ovh` on prod). Auth column
refers to the model described in [authentication.md](authentication.md).

## core
| Service | Role | Auth |
|---------|------|------|
| Homepage | Dashboard / launcher | forwardauth (`one_factor`) |
| Dashy | Alternative dashboard | forwardauth (`one_factor`) |
| Traefik | Ingress controller + dashboard | bypass |

## security
| Service | Role | Auth |
|---------|------|------|
| Authelia | Auth portal (forwardauth + OIDC provider) | bypass (is the portal) |
| LLDAP | User/group directory (Authelia backend) | own admin UI |
| Vaultwarden | Password manager | **OIDC** (SSO) |

## dev-tools
| Service | Role | Auth |
|---------|------|------|
| BookStack | Wiki / docs | **OIDC** |
| Wiki.js | Wiki | **OIDC** |
| Outline | Team knowledge base | **OIDC** |
| CloudBeaver (dbeaver) | DB web client | own login (`dev_user`); pinned 24.3.5 |
| IT-Tools | Dev utilities | bypass |
| CyberChef | Data-format swiss-army knife | bypass |
| whoami | Debug echo endpoint | forwardauth (`dev_user`) |
| ~~Headroom~~ | LLM context-compression proxy ([headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom)) | **disabled** — CLI-only, no working client; see [src/dev-tools/README.md](../src/dev-tools/README.md#headroom--disabled-cli-only-no-working-client-yet) |

## media
| Service | Role | Auth |
|---------|------|------|
| Jellyswarrm | Federation proxy in front of Jellyfin backends, benchmark-only (prod only) | own auth (bypass ingress); own hostname (`jellyswarrm.<domain>`), NOT in the path of real Jellyfin traffic — see [docs/media/jellyswarrm.md](media/jellyswarrm.md) |
| Jellyfin | Media server, host-native on mini4 (GPU transcode) | own auth (bypass ingress) + optional LLDAP login via LDAP-Auth plugin — see [jellyfin-ldap.md](media/jellyfin-ldap.md) |
| jellyfin-k8s | In-cluster Jellyfin, benchmark-only (prod only) | not exposed — internal, jellyswarrm backend only |
| Jellyseerr | Request manager | own auth (bypass ingress) |
| Radarr / Sonarr / Readarr | *arr automation | own auth (`media_user`) |
| Prowlarr | Indexer manager | own auth (`media_user`) |
| Bazarr | Subtitles | own auth (`media_user`) |
| Mediarvester | Media tooling | `mediarvester_user`; `mediarvester_admin`/`media_admin`/`admins` grants in-app admin |
| Tdarr | Media transcoding / normalization | `media_user` |
| Reclaimerr | *arr cleanup | **OIDC** (`media_user`) |
| Kavita | Comic/book/manga reader | **OIDC** (`media_user`) |
| Audiobookshelf | Audiobook/podcast server | **OIDC** (`media_user`) |
| Suwayomi | Manga downloader (feeds Kavita) | none / forwardauth (`media_user`) |
| ~~Komga~~ | Comic reader | **disabled** (replaced by Kavita) |
| Flaresolverr | Cloudflare solver (internal) | bypass (cluster CIDR only) |

## files
| Service | Role | Auth |
|---------|------|------|
| Transmission | Torrent client | own auth (`download_user`) |
| qBittorrent | Torrent client | own auth (`download_user`) |
| Deluge | Torrent client | own auth (`download_user`) |
| SABnzbd | Usenet client, auto-wired into Sonarr/Radarr/Readarr/Prowlarr | own auth (`download_user`) |

## games
| Service | Role | Auth |
|---------|------|------|
| RomM | ROM library manager | **OIDC** (`media_user`) |
| PokéClicker | Browser game | forwardauth (`one_factor`) |
| Unbegotten | 3D maze wrapped onto the inside of a sphere, browser game | forwardauth (`one_factor`) |
| Palworld | Dedicated Palworld game server | direct UDP (LoadBalancer/externalIP) |
| Minecraft | Vanilla + CurseForge modpack instances, any subset at once, fronted by `mc-router` | direct TCP via mc-router (LoadBalancer/externalIP), hostname-routed, no ingress |
| Valheim | Dedicated Valheim game server | direct UDP (LoadBalancer/externalIP) |
| Terraria | Dedicated Terraria game server | direct TCP+UDP (LoadBalancer/externalIP) |
| Satisfactory | Dedicated Satisfactory game server | direct TCP+UDP (LoadBalancer/externalIP) |

## observability
| Service | Role | Auth |
|---------|------|------|
| Grafana | Dashboards | **OIDC** (`dev_user`); `grafana_admin`/`dev_admin`/`admins` seen by the dashboard scope-shim as admin (see [observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md)) |
| Mimir | Metrics store (OTLP) | `dev_user` |
| Loki | Logs store | `dev_user` |
| Tempo | Traces store (pinned 2.10.6) | `dev_user` |
| OpenTelemetry Collector | Telemetry gateway | internal |
| Uptime-Kuma | Status / uptime monitoring | own login (`dev_user`) |

## persistence
Shared stateful backends (no public ingress): MariaDB / PostgreSQL / Redis
instances consumed by the apps above, plus the NFS-backed PVCs
(`apps`, `media`) on dev hostPath / prod Synology NFS.
