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
exactly.

**Layout:** a nested tree mirroring the repo — one document per directory
(a directory's own `README.md` becomes that document's body; otherwise the
directory doc is a stub linking to GitHub's tree view) and one child
document per `.md` file (title = filename without extension). Documents are
matched by their full title path, so a rename in git is a delete+create in
Outline. Repos with `rooted: true` nest under a top-level document named
after the repo, letting several small repos share one collection (`git:
images`) while each sync run only manages its own subtree. Dot-directories
and `CLAUDE.md` files (agent instructions, not human docs) are skipped.

**Change detection & limits:** every file document's banner links back to
its GitHub source and ends in a `sync:<hash>` token — Outline normalizes
stored markdown, so raw text comparison would re-update everything nightly;
the hash survives normalization and unchanged files are skipped. Writes
that trip Outline's rate limit (429) wait out the `Retry-After` window and
retry. Collections are created with `permission: read`, so members browse
but only git changes content.

**Private repos (`infra-as-code`):** repos marked `private: true` clone
over SSH using the key in `outline.sync.deployKey` (per-env, like
`apiToken`; rendered into the `outline-sync-ssh` Secret). The public half
is deploy key `158015333` on `platypod/infra-as-code` — **read-only**,
revocable in that repo's settings. Note: the platypod org had
`deploy_keys_enabled_for_repositories: false`; it was enabled org-wide
(2026-07-22) to allow this — re-disabling it kills the key and the infra
mirror silently. Without a `deployKey` in values, private repos are
skipped, not failed.

**Enabling per env (one manual step):** the CronJob renders only when
`outline.sync.apiToken` is set. Log into Outline as an admin → *Settings →
API* → create a token, put it in `values/<env>/values.yaml` under
`outline.sync.apiToken`, redeploy dev-tools. Until then the whole thing is a
no-op.

**Deliberate v1 limits:** flat document list per collection (no directory
nesting); relative links between docs are left as-is (they don't resolve
inside Outline — the banner's GitHub link is the escape hatch); images
referenced by docs aren't uploaded. Revisit if the mirror gets real use.
