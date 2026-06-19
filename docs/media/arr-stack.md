# *arr stack (media): sonarr / radarr / prowlarr / readarr / bazarr / flaresolverr

The acquisition apps. Grouped here — they share the same pattern.

- **Images:** LinuxServer `:latest` (**unpinned**) for sonarr/radarr/prowlarr/bazarr;
  **readarr is replaced by `ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.20.129`**
  (a maintained fork — upstream Readarr is end-of-life). flaresolverr is
  `flaresolverr/flaresolverr:latest`.
- **Auth:** all are on the Authelia **`bypass`** list — they expose their own API/auth
  and forward-auth would break inter-app API calls (Prowlarr→*arr, Bazarr→*arr,
  Jellyseerr→*arr). See [authelia](../security/authelia.md).
- **Storage:** config dirs on the local `config` volume (SQLite); library/downloads on
  the NFS `media` share.
- **Ports:** standard (sonarr 8989, radarr 7878, prowlarr 9696, bazarr 6767,
  flaresolverr 8191) — each with a host via Traefik.

**Maintenance note:** these `:latest` tags are the main deviation from the
pin-everything convention.
