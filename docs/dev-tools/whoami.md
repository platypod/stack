# whoami (dev-tools)

`traefik/whoami` — a tiny echo service that returns request/headers info. Used to
debug ingress, TLS, and Authelia forward-auth header injection.

- **Image:** `traefik/whoami`.
- **Exposure:** host via Traefik.
- No storage, no config — diagnostic only.
