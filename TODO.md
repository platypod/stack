- Trust the mkcert CA and create the TLS secret: run `make setup-dev-tls`
  once per dev machine (prompts for sudo to install the CA in macOS Keychain).
  Renew the same way when the cert expires (~3 years).
- Refresh PV nodeAffinity on dev: the `dev-apps` and `dev-media` PVs were
  deployed before the label-based nodeAffinity was introduced and still use
  `kubernetes.io/hostname: talos-juq-rvt`. Run `make deploy MODULE=persistence`
  to update them to `platypod.io/local-storage=true`.
- Fix hardcoded `allowed_origins: https://*.platypod.ovh` in
  `src/security/templates/authelia/authelia--config-map.yaml` — should use the
  env-specific domain (`{{ .Values.traefik.domain }}`) so dev OIDC clients can
  use `platypod.local` without being rejected by the CORS policy.
- Deploy remaining modules: observability, dev-tools, files, media, games.
  Each needs `make deploy MODULE=<name>`; they will also pick up the URL suffix
  removal (no more `-dev`) on first deploy.
- Ajouter la configuration de la persistence
    - Proposer une version script, avec un mode interactif et un mode non-interactif grâce à des variables d'environnements ou arguments.
    - Proposer une version documentaire de la procédure.
- Documenter le besoin d'installer les CRDs Traefik pour le middleware d'Authelia
- Documenter les pics de traffic liés au crawling après la signature de certificats LE https://acme-staging-v02.api.letsencrypt.org/acme/chall/185205204/16091071464/G1RTuw
- Ajouter la gestion des langues et des sous-titres à la stack multimédia - Voir https://github.com/PCJones/radarr-sonarr-german-dual-language?tab=readme-ov-file#i-dont-want-dual-language-i-want-to-prefer-german-but-use-english-as-fallback-or-vice-versa
- Ajouter l'activation/désactivation des utilisateurs par défault sur Authelia
- Créer plusieurs utilisateurs et compartimenter les droits sur la postgresql transverses (dev-tools)
- Corriger la configuration initiale de DBeaver (et sa base de donnée utilisée ? Plutôt que son schéma)
- S'assurer que les PVC sont configurables par les values et non en dur dans les templates
- Déporter les exporters de métriques dans des conteneurs dédiés dans les pods des applications supervisées (eg. prometheus-json-exporter pour jellyfin)
- Revoir la gestion de l'authentification RPC de transmission (actuellement désactivée en dur dans la ConfigMap, mais les credentials restent)
- Revoir le mapping de NodePort pour Transmission (actuellement le même NodePort pour TCP et UDP sur le peer-listening port, ce qui ne fonctionne pas avec toutes les versions de K8S)
- Etudier la notion de VLan pour relier les workers du projet