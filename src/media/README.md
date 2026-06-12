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

Reclaimerr and Kavita delegate login to Authelia. Both use the `hostAliases`
discovery trick (public Authelia host → `traefik.loadBalancerIP`). See
[docs/authentication.md](../../docs/authentication.md).

Kavita stores its OIDC config in the DB, not env — the **`kavita-setup` Job**
(post-install/upgrade hook, weight 15) registers the admin and pushes the OIDC
config via the settings API. It's idempotent and best-effort: OIDC failures don't
fail the release (retried next deploy). Kavita validates the issuer cert at
save-time, so OIDC can't be configured on dev (mkcert self-signed) — prod only.

## Komga → Kavita

Komga is **disabled** (`enable: false`); Kavita replaces it. Komga's data is
preserved (not deleted), so it can be re-enabled if needed.

## Suwayomi (manga downloader)

Feeds Kavita: downloads land as **CBZ** in the media share's `manga` subfolder
(`suwayomi.mangaSubPath`), which Kavita serves as a library.

- Runs as its **native uid 1000** — the bundled JAR at `/home/suwayomi/startup`
  is mode `0750` (owner-only), so custom uids can't launch it. Downloads end up
  `1000:1000` but world-readable, so Kavita (media user) still serves them.
- `AUTH_MODE=none` — gated solely by Authelia forward-auth.
- Reuses the shared **Flaresolverr** to bypass Cloudflare.

## Setup Jobs

Several services bootstrap via post-install/post-upgrade hook Jobs (idempotent,
exit 0 on partial so the release succeeds): `jellyfin-setup` (w10),
`kavita-setup` (w15), `jellyseerr-setup` (w20), `reclaimerr-setup` (w30).

## Flaresolverr

Internal-only (Authelia `bypass` restricted to the cluster CIDR). Shared by the
indexers and Suwayomi to solve Cloudflare challenges.
