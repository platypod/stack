# TODO

Consolidated backlog for the service stack. Cluster/infra TODOs live under
[`infra/`](../../infra/).

## Soon

- **Trust the mkcert CA (dev only).** Run `make setup-dev-tls` once per dev
  machine (sudo, installs the CA in the macOS Keychain). Renew the same way when
  the cert expires (~3 years).
  - Side effect of *not* trusting it: **Kavita OIDC cannot be validated on dev**
    — Kavita fetches the issuer discovery doc at save-time and rejects the
    self-signed cert. Works on prod (real Let's Encrypt cert). Dev limitation only.

- **Secrets management (CRITICAL — security risk).** All secrets are plaintext in
  Git, including prod credentials in `values/prd/values.yaml` (DB passwords, API
  keys, OIDC client secrets, admin tokens).
  **Fix:** SOPS + `age` (Helmfile has native support):
  1. `age-keygen -o ~/.config/sops/age/keys.txt`
  2. Add `.sops.yaml` with `encrypted_regex: 'password|secret|apiKey|key|passwordHash|token'`
  3. `sops -e --in-place values/prd/values.yaml` (and dev)
  4. Switch the secret value files from `values:` to `secrets:` in helmfile.

- **Default-user enable/disable on Authelia** — add lifecycle management for the
  default users (activation / deactivation) in LLDAP/Authelia.

- **Document LE crawl traffic spikes** seen after certificate signing.
  (ref: `acme-staging-v02.api.letsencrypt.org/acme/chall/185205204/...`)

- **Language & subtitle handling for the media stack** —
  https://github.com/PCJones/radarr-sonarr-german-dual-language

- **Move metric exporters into dedicated sidecar containers** within the
  supervised app pods (e.g. `prometheus-json-exporter` for Jellyfin).

- **Investigate VLANs** to interconnect the project's workers.

---

## Later / Potential additions

- **Observability alerting (alertmanager + rules).** The OTLP stack (Mimir, Loki,
  Tempo, Grafana) is deployed but has no alert rules or notification routing. Add
  an alerting engine + Alertmanager; define rules for disk pressure, crash-looping
  pods, and service downtime. Module: `observability`.

- **Paperless-NGX** (document management): OCR/tag/search. Needs PostgreSQL +
  Redis + a documents PVC. Module: new `home` or `dev-tools`.

- **Immich** (self-hosted photos): Google Photos alternative. Heavy — needs its
  own PostgreSQL with pgvector, Redis, and an ML worker. Module: `media` or
  standalone.

- **Jellyfin hardware transcoding.** Currently CPU-only. Investigate whether
  vfkit + Talos can pass through the Apple Silicon VideoToolbox engine; if so,
  expose `/dev/dri` and switch to the hardware-accelerated image variant.

- **Usenet download client (SABnzbd / NZBGet)** if usenet indexers are used via
  Prowlarr. Module: `files`.

- **Talos / Kubernetes in-place upgrade path.** Bumping `talos_version` forces VM
  recreation (loses etcd). Add a `make upgrade` target running `talosctl upgrade`
  per node in rolling order (workers first, control planes last).

---

## Recently done

- Per-module service/job docs under `docs/<module>/` — one page per workload
  (role + non-default config + quirks), 59 pages across all 8 modules (2026-06).
- OIDC expansion: RomM, Reclaimerr, Vaultwarden, Kavita (2026-06).
- Kavita + Suwayomi deployed; Komga disabled (`enable: false`).
- Service version bumps + pinning (no `latest`), except CloudBeaver.
- SQLite app DBs moved off NFS to a local `config` volume (Kavita/Vaultwarden/
  Uptime-Kuma/Bazarr) — fixes WAL-on-NFS lag/locks/crashes; nightly backup to NFS.
- Uptime-Kuma monitors seeded via hook Job (pinned to 1.23.x — 2.x dropped the
  Socket.io API).
