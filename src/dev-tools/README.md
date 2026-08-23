# dev-tools module

Documentation, database tooling and assorted dev utilities.
See [docs/services.md](../../docs/services.md) for the catalog.

## OIDC services

BookStack, Wiki.js and Outline all delegate login to Authelia via
OIDC. Clients are declared in the security module's Authelia ConfigMap; per-env
credentials live in `values/{dev,prd}/values.yaml`. See
[docs/authentication.md](../../docs/authentication.md).

- **Outline** has *no* local login path — OIDC is mandatory.
- **Wiki.js** version is pinned to whatever is currently running; check before
  bumping — downgrading the image downgrades its Postgres schema.

## CloudBeaver (dbeaver)

Pinned to **24.3.5** and intentionally **excluded from version bumps** — newer
releases have broken the saved-connection store in the past. Keeps its own admin
login (behind Authelia `dev_user`).

## Stateful backends

BookStack, Wiki.js and Outline each have their own DB (and Outline a Redis). The
`*-db` admin endpoints are exposed only to `dev_user`.

## whoami

Debug echo service (`dev_user`) — useful for verifying forward-auth headers and
routing without touching a real app.

## Headroom — **disabled** (CLI-only, no working client yet)

[headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom), an LLM
context-compression proxy. Chart is in place
(`values/default/dev-tools/headroom.yaml`, `headroom.enable: false`) but not
deployed. Runs in **proxy mode only** (`headroom proxy`, the image's default
entrypoint) — no qdrant/neo4j (those back the cross-agent memory feature) and
no persistent volume for `~/.headroom`, so its savings/memory stats would reset
on pod restart. Bypasses Authelia like IT-Tools/CyberChef: it'd be called by
CLI/agent traffic carrying an upstream API key, not a browser session.

**Only the terminal `claude` CLI can be pointed at it.** `ANTHROPIC_BASE_URL`
has to be set in `~/.claude/settings.json`'s `env` block (`make proxy-on
ENV=dev` / `make proxy-off`, via `bin/set-claude-proxy.sh`) — a shell `export`
doesn't work, since Claude Desktop doesn't inherit terminal environment.
**Claude Desktop cannot be routed through it at all**: it hardcodes
`ANTHROPIC_BASE_URL=https://api.anthropic.com` for every embedded `claude`
process it spawns, regardless of `settings.json` or even a session-wide
`launchctl setenv`. Confirmed by process tree: both a resumed and a brand-new
Desktop session, launched *after* the env var was set, still showed the
hardcoded default, and Headroom's own `/stats` request counter never moved for
either. There's no known way to override this from outside the app.

To pick this back up: flip `headroom.enable: true`, `make deploy ENV=dev
MODULE=dev-tools`, then use the terminal CLI only. See
[docs/make-targets.md](../../docs/make-targets.md).
