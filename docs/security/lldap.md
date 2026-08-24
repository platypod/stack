# lldap (security)

Lightweight LDAP — the single source of users/groups that Authelia binds against.

- **Image:** `lldap/lldap:stable`.
- **Storage:** Postgres (`postgres:17`, `lldap-db`).
- **Base DN:** `dc=platypod,dc=home`. Bind user is always
  `uid=admin,ou=people,<baseDn>` (`adminPassword`).
- **`jwtSecret`** — signs LLDAP's own web sessions (placeholder in default values).

## Seeding
Groups + users are created by the [lldap-seed-job](lldap-seed-job.md) (post-install
hook). **Prod seed users live in `values/prd/values.yaml`**, NOT the default
`lldap.yaml` (prod overrides it entirely) — including the **`otel-telemetry` service
account** used by the OTLP Basic-auth path (see [decisions.md](../decisions.md)) and the
**`jellyfin-ldap`** read-only bind account (prod-only, added there specifically —
see [../media/jellyfin-ldap.md](../media/jellyfin-ldap.md)).

## LDAPS (`lldap.ldaps.enable`, prod only)
Raw LDAP (port 3890) is cluster-internal only. External LDAP clients (prod's
host-native Jellyfin) go through Traefik's dedicated `ldaps` TCP entrypoint
(`:636`, TLS-terminated with the same trusted wildcard cert as everything else,
plaintext forwarded to this Service inside the cluster) rather than a raw
exposed port — see [../media/jellyfin-ldap.md](../media/jellyfin-ldap.md) for
the full rationale and the `IngressRouteTCP`.

## Gotchas
- Passwords are only set on **user creation**; existing users keep theirs (re-running
  the seed won't reset a password).
