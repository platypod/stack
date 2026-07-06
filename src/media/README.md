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

Feeds Komga: downloads land as **CBZ** in the media share's `manga` subfolder
(`suwayomi.mangaSubPath`), which Komga serves as a library.

- Runs as its **native uid 1000** — the bundled JAR at `/home/suwayomi/startup`
  is mode `0750` (owner-only), so custom uids can't launch it. Downloads end up
  `1000:1000` but world-readable, so Komga (media user) still serves them.
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
(w20), `reclaimerr-setup` (w30).

## Flaresolverr

Internal-only (Authelia `bypass` restricted to the cluster CIDR). Shared by the
indexers and Suwayomi to solve Cloudflare challenges.
