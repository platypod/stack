# dev-tools module

Self-hosted knowledge bases, utilities, and a DB client.

## Services
| Service | Image | Notes |
|---|---|---|
| [bookstack](bookstack.md) | `lscr.io/linuxserver/bookstack:latest` | wiki; MySQL + role-seed Job |
| [wikijs](wikijs.md) | `ghcr.io/requarks/wiki:2.5.314` | wiki; Postgres + OIDC-seed Job |
| [outline](outline.md) | `outlinewiki/outline:latest` | wiki; Postgres + Redis |
| [dbeaver](dbeaver.md) | `dbeaver/cloudbeaver:24.3.5` | web DB client; **left unpinned-by-policy exception elsewhere — here it IS pinned** |
| [it-tools](it-tools.md) | `corentinth/it-tools:latest` | dev utilities (static) |
| [cyber-chef](cyber-chef.md) | `ghcr.io/platypod/cyber-chef:v11.0.0` | **custom** image |
| [whoami](whoami.md) | `traefik/whoami` | debug echo service |
| [postgres](postgres.md) / [mysql](mysql.md) / [redis](redis.md) | `postgres:17` / `mysql:9` / `redis:7-alpine` | per-app backing stores |

## Jobs
- [bookstack-role-seed-job](bookstack-role-seed-job.md)
- [wikijs-oidc-seed-job](wikijs-oidc-seed-job.md)
