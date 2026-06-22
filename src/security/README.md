# security module

Services: Adguard, Authelia, LLDAP, Vaultwarden

## Vaultwarden — password manager

Bitwarden-compatible vault. Login delegates to Authelia via the OIDC `code` flow
with `offline_access` (SSO) — the master-password vault is unchanged; OIDC governs
*access* to the web vault. The OIDC client is declared in the Authelia ConfigMap;
per-env credentials live in `values/{dev,prd}/values.yaml`. SQLite DB lives on the
local `config` volume (NFS can't host SQLite WAL).

## Adguard — DNS design

**Chosen approach: NodePort DNS forwarding.**
The home router forwards DNS queries to the server IP on Adguard's NodePort.
Adguard rewrites `*.platypod.local` / `*.platypod.ovh` to the Traefik LoadBalancer IP
and forwards everything else to upstream resolvers (1.1.1.1 / 8.8.8.8).

NodePort is used (rather than a second LoadBalancer) because on single-node clusters
(e.g. dev), MetalLB / the host can only bind one LoadBalancer IP per interface —
Traefik already holds the primary one.

**Not chosen: DNS-over-HTTPS via Traefik.**
Would route DNS queries through Traefik's HTTPS endpoint (`adguard.domain:443/dns-query`).
Rejected: adds a circular dependency (DNS must resolve before Traefik is reachable).

## LLDAP — password management

LLDAP does **not** update the admin password from the `LLDAP_LDAP_USER_PASS` environment
variable if the database already exists. To change the admin password after first boot,
exec into the LLDAP container and run:

```sh
/app/lldap_set_password \
  --base-url http://localhost:17170 \
  --admin-username admin \
  --admin-password <current-password> \
  --username admin \
  --password <new-password>
```

The seed Job handles non-admin user passwords via the same binary (copied via init container).
