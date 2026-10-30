# komga-setup (Job)

Post-install/upgrade hook (also re-run daily by the `komga-reconcile` CronJob,
same script) that claims the Komga admin (if unclaimed), creates
any library declared in `komga.libraries` that doesn't already exist, grants
admin roles to LLDAP `admins` members, and (with OIDC) hides the local login.

- **Template:** `src/media/templates/komga/komga--setup-job.yaml`
- Idempotent: never touches a library that already exists — manual tweaks
  made from the admin UI afterward are left alone.
- Gated on `komga.credentials.email`/`password` being set — if Komga was
  claimed by hand before this Job existed, these must match the real admin
  login, or every call 401s (the Job logs a warning and exits 0 rather than
  crash-looping).

## Users and library access

Komga's OIDC auto-creation is **off** (`oauth2-account-creation: false` in
`komga--deployment.yaml`): an auto-created account sees every library, so
there'd be a window between a first login and the next reconcile. Instead the
script reads **live LLDAP** (GraphQL, admin login — hand-created users count,
the seed is not consulted) and, per LLDAP user matched to a Komga account by
email:

- in a group of `komga.access.groups` (`komga_bds` → `bds`, `komga_ebooks` →
  `ebooks`, `komga_mangas` → `mangas`): create the account if missing (random
  password, OIDC-only login; admin roles too if in `komga_admin`), then pin its
  shared libraries to the **union** of its groups' libraries
  (`sharedAllLibraries: false`). An OIDC login later matches that account by
  email; an unknown email is refused.
- in `komga.access.adminGroup` (`komga_admin`): add the full admin roles.
  This is deliberately **not** the global LLDAP `admins` group: a Komga admin
  bypasses the shared-libraries list and sees **every** library (verified on
  1.25.0), so admin must be handed out only to people who may see everything.
  Library pinning for such an account is moot. Roles are add-only: taking
  someone out of `komga_admin` does not demote them — remove the role by hand
  in Komga (Settings → Users).
- in no `komga_*` group: no account is created, an existing one is left alone.

It never deletes, disables or demotes anything, and never touches an account
whose email isn't in LLDAP (e.g. the `komga.credentials` bootstrap account).
Library access is declarative: a change made by hand in the Komga UI for a
`komga_*` user is reverted on the next run. Group → library mapping is
`komga.access.groups` in `apps/base/values/media.yaml`; the groups themselves are
generated into LLDAP from it. To give someone access: add them to the group in
LLDAP (and, if you want it in Git, in the seed); it takes effect on the next
deploy or the daily run (`komga.reconcile.schedule`, 04:17).

A failure reaching LLDAP (HTTP error or connection refused) skips the user step
(warn, exit 0) and the rest of the script still runs.

## Dashboard default (global)

Komga's home page layout is a *client setting*: `webui.recommended.all` (and
`webui.recommended.<libraryId>` per library view), a JSON `{"sections": [...]}`.
The web UI reads `{...global, ...user}`, so a **global** value is the default for
everyone who hasn't edited their own dashboard (pencil icon, a per-user
setting that wins over it). `komga.dashboard.sections` in values is that default
(order matters); it currently keeps only `KEEP_READING`, `ON_DECK` and
`RECENTLY_READ_BOOKS` (the "Recently Added/Released/Updated" ones are left out). The Job rewrites it only when it differs; an empty list
leaves Komga's default (all seven sections) alone. Which libraries the "all"
dashboard draws from follows each user's *pinned* libraries, a user-only setting
(no global equivalent found in the web UI code). Untested
end-to-end: a real OIDC login landing on a pre-created account.

See [komga](komga.md).
