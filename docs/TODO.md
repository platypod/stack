# TODO

Consolidated backlog for the service stack. Cluster/infra TODOs live under
[`infra/`](../../infra/).

## Soon

- **Per-theme Mimir tenants (e.g. `k8s` / `ai` / `services`).** Right now Mimir is
  single-tenant (`multitenancy_enabled: false`) — *every* metric family (cluster
  infra: kubeletstats/traefik/k8s_cluster, `ai_tx_*` transcript telemetry,
  per-service exporters) shares one bucket, so there is no way to wipe-and-rebuild
  one family (e.g. re-deriving `ai_tx_*` from the local Claude transcripts after a
  shipper bug) without nuking a year of unrelated cluster history too. Mimir also
  has no delete-series-by-label API at all (confirmed: not implemented,
  [grafana/mimir#4968](https://github.com/grafana/mimir/issues/4968)), so a bad
  label value currently just has to age out via retention.
  **Proposal:** split by *write source*, not by user — flip
  `multitenancy_enabled: true` and have the OTLP gateway stamp `X-Scope-OrgID`
  per metric family the same way it already stamps Loki's `claude-<user>` tenant
  for transcripts (see
  [docs/observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md)).
  This does **not** contradict that doc's "rejected: full multi-tenancy for
  everything" call — that rejection was specifically about *per-user* metric
  tenants fighting admin-sees-everything and being structurally wrong for
  co-mingled scrapes (Jellyfin). Per-theme tenants are a few, static, and
  orthogonal: the existing `owner`-label + prom-label-proxy isolation would still
  run *inside* the `ai` tenant for per-user scoping; the tenant wall only buys a
  safe blast radius for bulk operations (delete/rebuild one theme without
  touching the others). Needs: theme taxonomy definition, gateway routing rule
  per metric family, admin federated-read config (small fixed tenant list, unlike
  the dynamic per-user Loki case), and an update to dashboard-multitenancy.md
  recording this as an accepted extension once implemented.

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

- **Backups + key durability review (esp. Vaultwarden).** Vaultwarden's SQLite
  vault is on a **node-local** volume (NFS can't host SQLite WAL), protected only
  by the nightly config-backup → NFS (so up to ~24h exposure, and the NFS copy is
  a SQLite snapshot, not point-in-time). Review: (a) backup cadence/restore drills
  for the local SQLite apps; (b) where Vaultwarden's data lands and how to
  recover it; (c) **securing the primary/key material** — the Vaultwarden admin
  token + the broader plaintext-secrets-in-Git problem (ties into the SOPS item
  above). Decide what the "primary key" is (SOPS age key? a backup-encryption
  key?) and how it's stored/rotated/escrowed off-cluster.

- **Review architectural decision-records management.** Want a cleaner view of
  every decision taken — against which alternatives, and why. Currently split
  across [decisions.md](decisions.md) (new), [authentication.md](authentication.md),
  the per-feature deep-dives (e.g. [observability/dashboard-multitenancy.md](observability/dashboard-multitenancy.md)),
  and [`infra/docs/decisions.md`](../../infra/docs/decisions.md). Consider a
  consistent ADR format/index spanning both subsystems.

- **Document LE crawl traffic spikes** seen after certificate signing.
  (ref: `acme-staging-v02.api.letsencrypt.org/acme/chall/185205204/...`)

- **Language & subtitle handling for the media stack** —
  https://github.com/PCJones/radarr-sonarr-german-dual-language

- **Move metric exporters into dedicated sidecar containers** within the
  supervised app pods (e.g. `prometheus-json-exporter` for Jellyfin).

- **Investigate VLANs** to interconnect the project's workers.

- **Palworld/Minecraft internet-facing access.** Both are LAN-only right now —
  `chuwi-cp1`'s externalIP is reachable inside the network (AdGuard's
  `*.platypod.ovh` wildcard covers Minecraft's per-instance hostnames
  automatically for LAN clients), but nothing forwards the ports from the
  router yet: Palworld needs UDP `8211`+`27015`, Minecraft/mc-router needs TCP
  `25565`, both to `192.168.1.156`. Also needs real public DNS records per
  enabled Minecraft instance hostname (`vanilla.platypod.ovh`, etc.) — AdGuard
  only helps LAN clients.

- **Verify CurseForge `fileId` pins before enabling bcgplus/cobbleverse.**
  `values/default/games/minecraft.yaml` pins specific file IDs found via a
  CurseForge page fetch on 2026-07-31 (BCG+ 2.15.0 / Cobbleverse 1.7.42) —
  confirm on curseforge.com that these are still the intended files (there are
  several similarly-named "BigChadGuys"/"Cobbleverse" packs by other
  uploaders) before flipping `enable: true` on either.

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

- **Pick a Usenet block-account (NNTP) provider** and fill in
  `sabnzbd.provider.*` in `values/dev/values.yaml` / `values/prd/values.yaml`.
  SABnzbd + the Prowlarr/*arr auto-wiring are in place (`files` module,
  `sabnzbd-setup` Job); althub.co.za is a Newznab indexer only, not a Usenet
  server, so SABnzbd currently has nothing to fetch articles with.

- **Talos / Kubernetes in-place upgrade path.** Bumping `talos_version` forces VM
  recreation (loses etcd). Add a `make upgrade` target running `talosctl upgrade`
  per node in rolling order (workers first, control planes last).

- **Run `make setup-prod-dns` on the laptop.** Built and verified
  (2026-07-31) but not yet executed — the DNS flip needs an interactive
  `sudo` password, so it was left for the operator. Note: after switching a
  device's DNS to AdGuard, any hostname the Bbox self-answers for (e.g. its
  own admin UI, `mabbox.bytel.fr`) stops resolving unless mirrored as an
  AdGuard rewrite — already done for that one (`adguard.rewrites` in
  `values/prd/values.yaml`), but the same gotcha will hit any other
  Bbox-hijacked name.

- **Point other LAN devices (phones, etc.) at AdGuard.** The Bbox router can't
  set DHCP-assigned DNS, so every other device needs its DNS set by hand in
  its own network settings — outside what this repo can automate. Until then
  those devices get none of AdGuard's ad-blocking or the
  `*.platypod.ovh`/`k8s.platypod.lan` rewrites.

---

## Recently done

- **Palworld enabled in prod + Minecraft (`mc-router`) added (2026-07-31).**
  Palworld's chart gained `externalIP`/`nodeSelector` support (was
  MetalLB-only, prod has none — see `traefik.externalIP` for the mechanism)
  and an `extraEnv` passthrough for any `PalWorldSettings.ini`-mapped var;
  memory bumped to the image's real recommendation (`16Gi`/`32Gi`, was
  `4Gi`/`8Gi`); switched off the image's deprecated `MULTITHREADING` toggle.
  New `games/templates/minecraft/` chart supports named vanilla/CurseForge
  instances (any subset enabled at once) fronted by `itzg/mc-router`, which
  hostname-routes since Minecraft's protocol has no HTTP Host/TLS SNI for
  Traefik to use; needed a `ClusterRole` for its Service watch despite
  `KUBE_NAMESPACE` (see conventions.md pitfall). First instance live: vanilla
  MC 26.2 (Mojang's 2026 year-based versioning, not `1.21.x`) on Java 25.
  Both are LAN-only pending the router port-forward (see Soon, above).
- Per-module service/job docs under `docs/<module>/` — one page per workload
  (role + non-default config + quirks), 59 pages across all 8 modules (2026-06).
- OIDC expansion: RomM, Reclaimerr, Vaultwarden, Kavita (2026-06).
- Kavita + Suwayomi deployed; Komga disabled (`enable: false`).
- Service version bumps + pinning (no `latest`), except CloudBeaver.
- SQLite app DBs moved off NFS to a local `config` volume (Kavita/Vaultwarden/
  Uptime-Kuma/Bazarr) — fixes WAL-on-NFS lag/locks/crashes; nightly backup to NFS.
- Uptime-Kuma monitors seeded via hook Job (pinned to 1.23.x — 2.x dropped the
  Socket.io API).
