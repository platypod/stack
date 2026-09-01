# *arr stack (media): sonarr / radarr / prowlarr / readarr / bazarr / flaresolverr / shelfmark

The acquisition apps. Grouped here — they share the same pattern.

- **Images:** LinuxServer `:latest` (**unpinned**) for sonarr/radarr/prowlarr/bazarr;
  **readarr is replaced by `ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.20.129`**
  (a maintained fork — upstream Readarr is end-of-life). flaresolverr is
  `flaresolverr/flaresolverr:latest`.

## readarr/bookshelf → shelfmark migration (2026-09)

Bookshelf's metadata comes from `rreading-glasses`, routed through a shared
public proxy (`hardcover.bookinfo.pro`). That proxy has been intermittently
broken since January 2026 for the whole community — see
[pennydreadful/bookshelf#102](https://github.com/pennydreadful/bookshelf/discussions/102)
— and bookshelf itself hasn't been pushed to since 2026-02-04, so fixes for
this aren't coming from upstream. **Readarr is retired**: `readarr.enable`
defaults to `false` in `registry.yaml` (kept enable-able for a quick rollback
comparison, not removed outright). `shelfmark` replaces it — `enable: false`
by default in `registry.yaml`, opted in per-env via `platypod-sops`
(`true` on both `local` and `prd` as of the 2026-09 cutover).

- Different paradigm: **on-demand search/request tool**, not an
  author-monitor. No `apiKey`-gated homepage widget the way the *arrs have
  one — configured entirely via env vars, no seeded config file.
- Metadata comes from **Hardcover's official API directly**, using a
  personal token (`shelfmark.hardcover.apiKey`) — not the shared proxy. Get
  one free at hardcover.app/account/api (starts with `hc_pat_`); real value
  lives in `platypod-sops`, never in this repo's defaults.
- Image pinned to `ghcr.io/calibrain/shelfmark:v1.3.13` (unlike the rest of
  this module, which stays on unpinned LinuxServer `:latest` tags).
- Mounts the full `media` share at `{{ .Values.media.system.data.path }}`
  (same as readarr) plus a `/books` mount (subPath `books`) matching
  Shelfmark's own documented default volume layout.
- **Wired to Prowlarr and all three torrent clients**, each independently
  gated behind that service's own `.enable` flag so nothing breaks when one
  is off (only Transmission is actually on in either environment today;
  qBittorrent/Deluge are scaffolded and will pick up automatically the day
  either gets enabled — no template change needed):
  - `PROWLARR_ENABLED`/`PROWLARR_URL`/`PROWLARR_API_KEY` — only when
    `prowlarr.enable`.
  - `PROWLARR_TORRENT_CLIENT` picks the active client itself, preferring
    Transmission > qBittorrent > Deluge (whichever is enabled).
  - `TRANSMISSION_*` / `QBITTORRENT_*` / `DELUGE_*` connection + credential
    env vars, each behind its own service's `.enable` flag.
  - `ONBOARDING=false` — everything above is env-driven config, so
    Shelfmark's first-run setup wizard has nothing left to do. Confirmed
    against its own source (`shelfmark/core/onboarding.py`): unset,
    `is_onboarding_complete()` reads a flag from `settings.json`; set to
    `false`, it short-circuits to "already done" instead.
  - **Usenet**: `PROWLARR_USENET_CLIENT=sabnzbd` + `SABNZBD_URL`/`SABNZBD_API_KEY`,
    gated on `sabnzbd.enable`. Shelfmark doesn't need its own Newznab
    connection for this — it searches through Prowlarr's indexers directly,
    and althub.co.za (the Newznab indexer already in this stack) is wired
    into **Prowlarr itself** by the existing `sabnzbd-setup` Job
    (`prowlarr.indexers.althub.apiKey` in `media.yaml`/`platypod-sops`), not
    Shelfmark. On `local` that key is unset (althub inactive there) and
    SABnzbd has no usenet provider configured either — both pre-existing
    gaps, same "needs the user's own account" shape as the Hardcover token,
    unrelated to Shelfmark's own wiring. `prd` already has both.
- **Auth:** all are on the Authelia **`bypass`** list — they expose their own API/auth
  and forward-auth would break inter-app API calls (Prowlarr→*arr, Bazarr→*arr,
  Jellyseerr→*arr). See [authelia](../security/authelia.md).
- **Storage:** config dirs on the local `config` volume (SQLite); library/downloads on
  the NFS `media` share.
- **Ports:** standard (sonarr 8989, radarr 7878, prowlarr 9696, bazarr 6767,
  flaresolverr 8191) — each with a host via Traefik.

**Maintenance note:** these `:latest` tags are the main deviation from the
pin-everything convention.
