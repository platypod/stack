# security module

Identity + access for the whole stack: **LLDAP** (user directory) → **Authelia**
(auth gateway, forward-auth + OIDC) → every service behind Traefik.

## Services
- [authelia](authelia.md) — auth gateway (forward-auth, Basic, OIDC).
- [lldap](lldap.md) — lightweight LDAP user/group directory.
- [vaultwarden](vaultwarden.md) — Bitwarden-compatible password manager; OIDC (SSO).
- [postgres](postgres.md) — backing DB (one instance each for Authelia and LLDAP).
- [redis](redis.md) — Authelia session store.

## Jobs
- [lldap-seed-job](lldap-seed-job.md) — idempotently seeds groups + users.

Deep dive on the auth flows: [docs/authentication.md](../authentication.md). External
OTLP telemetry ingest auth is covered in [decisions.md](../decisions.md).
