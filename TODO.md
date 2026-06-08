## DONE (resolved — kept here for reference)

- **Refresh PV nodeAffinity on dev:** `make deploy MODULE=persistence` — done.
- **Fix hardcoded `allowed_origins: https://*.platypod.ovh`:** Already resolved;
  `allowed_origins_from_client_redirect_uris: true` is the correct approach.
- **Corriger la configuration initiale de DBeaver:** Fixed — wrong PVC reference
  (was `jellyseerr.pvc`, now `dbeaver.pvc`), `initial-data.conf` now mounted,
  `replicasNb` set to 1.
- **Créer plusieurs utilisateurs et compartimenter les droits sur la postgresql
  transverses:** Done — `jellyseerr`, `mediarvester` and `cloudBeaver` each have
  their own DB user now; superuser no longer shared to services.
- **S'assurer que les PVC sont configurables par les values:** Already the case —
  all `claimName:` references go through `.Values.*`.
- **Per-service enabled/disabled toggle:** Implemented — wrap templates with
  `{{- if .Values.service.enabled }}`; override in env values to disable.

---

## Soon

- Trust the mkcert CA and create the TLS secret: run `make setup-dev-tls`
  once per dev machine (prompts for sudo to install the CA in macOS Keychain).
  Renew the same way when the cert expires (~3 years).

- Deploy remaining modules after stack changes: observability, dev-tools, files,
  media, games. Each needs `make deploy MODULE=<name>`.

- **Secrets management (CRITICAL — security risk):**
  All secrets are currently plaintext in Git (including prod credentials in
  `values/prd/values.yaml`). This includes DB passwords, API keys, OIDC client
  secrets, and service admin tokens.
  **Recommended fix:** Integrate [SOPS](https://github.com/getsops/sops) + `age`.
  Helmfile has native SOPS support. Steps:
  1. Generate an age key: `age-keygen -o ~/.config/sops/age/keys.txt`
  2. Add `.sops.yaml` to the repo root specifying which keys to encrypt
     (`encrypted_regex: 'password|secret|apiKey|key|passwordHash|token'`).
  3. `sops -e --in-place values/prd/values.yaml` (and dev equivalent).
  4. In helmfile, switch secret value files from `values:` to `secrets:`.
  Files to encrypt: `values/prd/values.yaml`, `values/dev/values.yaml`,
  and any `values/default/*.yaml` containing non-placeholder credentials.

- **Transmission RPC auth disabled in ConfigMap:**
  `src/files/templates/transmission/transmission--config-map.yaml` hardcodes
  `rpc-authentication-required=false` despite credentials existing in values.
  Fix: set `rpc-authentication-required=true` and wire credentials from
  `.Values.transmission.credentials.*`.

- **Transmission NodePort TCP/UDP conflict:**
  The peer-listening port uses the same NodePort for both TCP and UDP, which
  does not work on some Kubernetes versions (port must be unique per protocol).
  Fix: assign distinct NodePort values for TCP and UDP in the Service template
  and `values/default/files/transmission.yaml`.

- Ajouter la configuration de la persistence
    - Proposer une version script, avec un mode interactif et un mode non-interactif grâce à des variables d'environnements ou arguments.
    - Proposer une version documentaire de la procédure.

- Documenter le besoin d'installer les CRDs Traefik pour le middleware d'Authelia

- Documenter les pics de traffic liés au crawling après la signature de certificats LE
  https://acme-staging-v02.api.letsencrypt.org/acme/chall/185205204/16091071464/G1RTuw

- Ajouter la gestion des langues et des sous-titres à la stack multimédia
  https://github.com/PCJones/radarr-sonarr-german-dual-language

- Ajouter l'activation/désactivation des utilisateurs par défault sur Authelia

- Déporter les exporters de métriques dans des conteneurs dédiés dans les pods
  des applications supervisées (eg. prometheus-json-exporter pour jellyfin)

- Etudier la notion de VLan pour relier les workers du projet

---

## Later / Potential additions

- **Observability alerting (vmalert + Alertmanager):**
  The OTLP observability stack (VictoriaMetrics, Loki, Tempo, Grafana) is
  deployed but there are no alert rules and no notification routing.
  Add `vmalert` (VictoriaMetrics's alert engine) + Alertmanager. Define rules
  for disk pressure, pod crash-looping, and service downtime.
  Module: `observability`.

- **Paperless-NGX (document management):**
  OCR + tag + search for scanned documents. Requires PostgreSQL (shared or
  dedicated), Redis, and a PVC for documents. Module: new `home` or `dev-tools`.

- **Immich (self-hosted photos):**
  Google Photos alternative. Heavy: needs its own PostgreSQL with pgvector,
  Redis, and an ML worker. Prod storage (18 Ti NFS) has ample headroom.
  Module: `media` or standalone.

- **Jellyfin hardware transcoding:**
  Current deployment is CPU-only (`jellyfin/jellyfin:latest`). On Apple Silicon
  (prod workers), VideoToolbox is theoretically available but requires the VM
  hypervisor (vfkit) to expose it. Investigate whether vfkit + Talos can pass
  through the codec engine; if yes, configure `/dev/dri` in the Jellyfin
  deployment and switch to the hardware-accelerated image variant.

- **Usenet download client (SABnzbd or NZBGet):**
  Three torrent clients are deployed. If usenet indexers are used via Prowlarr,
  a compatible download client is needed. Module: `files`.

- **Talos / Kubernetes in-place upgrade path:**
  Bumping `talos_version` in tfvars forces VM recreation (loses etcd). Add a
  `make upgrade` target that runs `talosctl upgrade` per node in rolling order
  (workers first, control planes last) and waits for each node to be `Ready`.
