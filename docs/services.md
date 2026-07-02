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
| CloudBeaver (dbeaver) | DB web client | own login (`group:dev`); pinned 24.3.5 |
| IT-Tools | Dev utilities | bypass |
| CyberChef | Data-format swiss-army knife | bypass |
| whoami | Debug echo endpoint | forwardauth (`group:dev`) |

## media
| Service | Role | Auth |
|---------|------|------|
| Jellyswarrm | Federation proxy in front of Jellyfin backends (prod only) | own auth (bypass ingress); owns `jellyfin.<domain>` |
| Jellyfin (`jellyfin-proxy` on prod) | Media server, host-native on mini4 (GPU transcode) | own auth (bypass ingress); direct route at `jellyfin-proxy.<domain>` |
| jellyfin-k8s | In-cluster Jellyfin, benchmark-only (prod only) | not exposed — internal, jellyswarrm backend only |
| Jellyseerr | Request manager | own auth (bypass ingress) |
| Radarr / Sonarr / Readarr | *arr automation | own auth (`group:media`) |
| Prowlarr | Indexer manager | own auth (`group:media`) |
| Bazarr | Subtitles | own auth (`group:media`) |
| Mediarvester | Media tooling | `group:media` |
| Reclaimerr | *arr cleanup | **OIDC** (`group:media`) |
| Kavita | Comic/book/manga reader | **OIDC** (`group:media`) |
| Suwayomi | Manga downloader (feeds Kavita) | none / forwardauth (`group:media`) |
| ~~Komga~~ | Comic reader | **disabled** (replaced by Kavita) |
| Flaresolverr | Cloudflare solver (internal) | bypass (cluster CIDR only) |

## files
| Service | Role | Auth |
|---------|------|------|
| Transmission | Torrent client | own auth (`group:download`) |
| qBittorrent | Torrent client | own auth (`group:download`) |
| Deluge | Torrent client | own auth (`group:download`) |

## games
| Service | Role | Auth |
|---------|------|------|
| RomM | ROM library manager | **OIDC** (`group:media`) |
| PokéClicker | Browser game | forwardauth (`one_factor`) |

## observability
| Service | Role | Auth |
|---------|------|------|
| Grafana | Dashboards | **OIDC** (`group:dev`) |
| Mimir | Metrics store (OTLP) | `group:dev` |
| Loki | Logs store | `group:dev` |
| Tempo | Traces store (pinned 2.10.6) | `group:dev` |
| OpenTelemetry Collector | Telemetry gateway | internal |
| Uptime-Kuma | Status / uptime monitoring | own login (`group:dev`) |

## persistence
Shared stateful backends (no public ingress): MariaDB / PostgreSQL / Redis
instances consumed by the apps above, plus the NFS-backed PVCs
(`apps`, `media`) on dev hostPath / prod Synology NFS.
