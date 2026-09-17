# media module

The media library and automation stack. See [docs/services.md](../../docs/services.md)
for the full list; this covers the non-obvious bits.

## Storage & ownership

All apps mount the shared **media** NFS PVC (`storage.defaultVolumes.media`) at
`media.system.data.path` (`/data`). Pods run as the **media user**
(`media.system.userId`/`groupId` — dev `501:20`, prod `1026:100`) so files are
shared with the *arrs.

> **NEVER set `fsGroup` on the NFS PVC pods** — it triggers a recursive chown of
> the whole (18 TB) Synology share. Use an `init-permissions` initContainer that
> chowns only the app's *own* subdirectory instead. See CLAUDE.md.

## OIDC

Reclaimerr, Komga, and Kavita all delegate login to Authelia and use the
`hostAliases` discovery trick (public Authelia host → `traefik.loadBalancerIP`).
See [docs/authentication.md](../../docs/authentication.md).

Komga's OIDC client is registered directly via env (`SPRING_APPLICATION_JSON`
in its Deployment) — no setup Job needed for that part.

Kavita stores its OIDC config in the DB, not env — the **`kavita-setup` Job**
(post-install/upgrade hook, weight 15) registers the admin and pushes the OIDC
config via the settings API. It's idempotent and best-effort: OIDC failures don't
fail the release (retried next deploy). Kavita validates the issuer cert at
save-time, so OIDC can't be configured on dev (mkcert self-signed) — prod only.

## Komga vs Kavita

Kavita (.NET) is **disabled** (`enable: false`) — it intermittently SIGILL-crashes
on the ARM guest, with no workaround found. **Komga (JVM) is the active
comics/manga reader** instead. Kavita's data/config is preserved (not deleted),
so it can be re-enabled if a future .NET build or vfkit fix resolves the SIGILL.

Komga library roots must each contain one subfolder per Series — books sitting
directly in a library's root all collapse into a single series named after the
root folder. The **komga-setup** Job (post-install/upgrade hook, weight 15)
creates the libraries declared in `komga.libraries` (idempotent,
create-if-missing only — see [docs/media/komga-setup-job.md](../../docs/media/komga-setup-job.md)).

## Suwayomi (manga downloader)

Feeds Komga: downloads land as **CBZ** in the top-level `mangas` folder
(`suwayomi.mangaSubPath`), which Komga serves as a library.

Unlike the *arrs there is **no import step** — Suwayomi is both the downloader
and the library manager, and it hard-codes its layout as
`<downloadsPath>/mangas/<source>/<series>/<chapter>.cbz` with a `thumbnails/`
alongside. So the deployment mounts **only** the `mangas` level from the share,
at `<downloadsPath>/mangas`, and leaves `<downloadsPath>` itself on the app
volume: Suwayomi's scratch stays off the media share, and the one NFS path it
can reach is the library folder. Until 2026-09-17 it owned the whole `manga/`
folder on the share, with the `bd` library parked inside it
([runbook](../../docs/media/comics-layout-migration.md)).

- Runs as its **native uid 1000** — not for the JAR's sake (that is `0777` and
  would run under any uid; an older note here claiming `0750` was wrong), but
  because the JCEF/Chromium cache dirs under `/home/suwayomi` are `0700` owned
  by that uid, and the JS-heavy sources need that browser.
- Its identity therefore matches neither the media user nor the laptop over NFS.
  Access is handled by **mode, not ownership**: the library folder is `2777` +
  setgid to `media.system.groupId`, and the container is re-exec'd under
  `umask 002` (the image default is `0022`, which is what used to leave every
  new series directory `0755` and locked the laptop out). The init container
  asserts the mountpoint's mode only — it must never `chown -R` the library.
- `AUTH_MODE=none` — gated solely by Authelia forward-auth.
- Reuses the shared **Flaresolverr** to bypass Cloudflare.

**Extension sources.** Suwayomi ships with no sources (the original Tachiyomi
repo was taken down), so you must add a third-party *extension repository*. The
`suwayomi-setup` Job (post-install/upgrade hook, weight 25) seeds the repos in
`suwayomi.extensionRepos` (default: keiyoushi) via Suwayomi's GraphQL API — the
same field as the WebUI's Settings → Browse → Extension Repositories. Requires
Suwayomi **≥ v1.0.0**; the extension-repo system did not exist in v0.7.x (the
image is pinned to v2.x). After the repo loads, enable a language on the
Extensions page and install the sources you want.

## Setup Jobs

Several services bootstrap via post-install/post-upgrade hook Jobs (idempotent,
exit 0 on partial so the release succeeds): `jellyfin-setup` (w10),
`komga-setup` / `kavita-setup` (w15, whichever's enabled), `jellyseerr-setup`
(w20), `reclaimerr-setup` (w30), `tdarr-setup` (w35).

## Flaresolverr

Internal-only (Authelia `bypass` restricted to the cluster CIDR). Shared by the
indexers and Suwayomi to solve Cloudflare challenges.
