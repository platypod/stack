# outline (dev-tools)

Outline — team knowledge base / wiki.

- **Image:** `outlinewiki/outline:latest` (**unpinned**).
- **Backing stores:** **both** [postgres](postgres.md) (`postgres:17`) and
  [redis](redis.md) (`redis:7-alpine`) — Outline needs both.
- **Auth:** Authelia OIDC (`utilsSecret`/`clientSecret` in values).
- **Exposure:** host via Traefik.

## Git mirror (`outline-sync` CronJob)

One-way nightly mirror of repo markdown into read-only Outline collections —
decision record in [../decisions.md](../decisions.md). An init container
(`alpine/git`) shallow-clones the repos listed in `outline.sync.repos`
(public — no git credential), then a stdlib-Python script
(`outline-sync` ConfigMap) reconciles each repo into its collection over the
internal Service: create/update/delete so the collection matches the repo
exactly. Document titles are repo-relative paths (the sync's matching key —
a rename is delete+create); every document opens with a banner linking back
to its source file on GitHub, ending in a `sync:<hash>` token — the change
detector (Outline normalizes stored markdown, so raw text comparison would
re-update everything nightly; the hash survives normalization, and unchanged
files are skipped). Writes that trip Outline's rate limit (429) are retried
after the window. Collections are created with `permission: read`, so
members browse but only git changes content.

**Enabling per env (one manual step):** the CronJob renders only when
`outline.sync.apiToken` is set. Log into Outline as an admin → *Settings →
API* → create a token, put it in `values/<env>/values.yaml` under
`outline.sync.apiToken`, redeploy dev-tools. Until then the whole thing is a
no-op.

**Deliberate v1 limits:** flat document list per collection (no directory
nesting); relative links between docs are left as-is (they don't resolve
inside Outline — the banner's GitHub link is the escape hatch); images
referenced by docs aren't uploaded. Revisit if the mirror gets real use.
