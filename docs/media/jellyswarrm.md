# jellyswarrm (media)

Federation reverse-proxy in front of multiple Jellyfin backends
([LLukas22/Jellyswarrm](https://github.com/LLukas22/Jellyswarrm)), deployed to
compare the host-native `jellyfin-proxy` instance against the in-cluster
`jellyfin-k8s` instance for performance.

- **Enabled:** prod only (`values/prd/values.yaml` → `jellyswarrm.enable`).
- **Image:** `ghcr.io/llukas22/jellyswarrm:latest`, port 3000.
- **Hostname:** deliberately **hardcoded to reuse `jellyfin.<domain>`**
  (`values/default/media/jellyswarrm.yaml` → `host`), not derived from its own
  `jellyswarrm` label — it replaces the Jellyfin route at the exact hostname
  real users/apps already point at. No Authelia middleware on its
  `IngressRoute`, matching the bypass behavior the direct Jellyfin route had
  before (Jellyfin does its own auth) — adding Authelia here would prompt
  users with a login they didn't previously have.
- **Storage:** local `config` volume (`storage.defaultVolumes.config`, subPath
  `jellyswarrm`) for its sqlite db.

## Backend registration — automated via config file, not a setup Job

Jellyswarrm's own admin UI ("add a server") is the documented path, but the
app also reads a TOML config at `$JELLYSWARRM_DATA_DIR/jellyswarrm.toml`,
layered under `JELLYSWARRM_*` env var overrides — see
[`config.rs`](https://github.com/LLukas22/Jellyswarrm/blob/main/crates/jellyswarrm-proxy/src/config.rs).
`preconfigured_servers` is a `Vec<PreconfiguredServer>`; the `JELLYSWARRM_PRECONFIGURED_SERVERS`
env var documented in `docs/config.md` has no confirmed working list syntax
against the `config` crate's `Environment` source as wired here (no
`list_separator` configured) — a struct array can't reliably come from a flat
env var. The TOML file has no such ambiguity (native array-of-tables), so
that's the mechanism used here.

The [config-map](../../src/media/templates/jellyswarrm/config-map.yaml) seeds
`jellyswarrm.toml` declaring both backends
(`jellyfin-proxy:8096` priority 10, `jellyfin-k8s:8096` priority 5), and the
[deployment](../../src/media/templates/jellyswarrm/deployment.yaml) copies it
onto the persistent `/app/data` volume **only if the file doesn't already
exist** — same "seed once, app owns it after" pattern as `jellyfin`'s
`system.xml` and Bazarr's `config.yaml`. Admin UI edits (streaming mode,
priority, adding real backends later) persist across restarts/redeploys.

**`merge_libraries = false` is set explicitly.** This is a *global* (not
per-user) setting — confirmed in
[`merged_library_service.rs`](https://github.com/LLukas22/Jellyswarrm/blob/main/crates/jellyswarrm-proxy/src/merged_library_service.rs) —
that merges same-`collection_type` libraries across **all** registered servers
into one virtual library. `jellyfin-k8s` scans the identical NFS media as
`jellyfin-proxy`; leaving the upstream default (`true`) would duplicate every
title for real users. This is the mechanism that makes "no impact on users"
actually hold, not just per-user federation opt-in.

**`media_streaming_mode` defaults to `Redirect`** (`jellyswarrm.streamingMode`
value) — the client streams directly from whichever backend is selected,
isolating each backend's own direct-play performance (the actual point of
this deployment). `Proxy` routes stream bytes through jellyswarrm too, adding
it to the measured path. Note: the upstream docs claim the *default* (when
`media_streaming_mode` is omitted) is `Redirect`, but `config.rs`'s
`default_media_streaming_mode()` actually returns `Proxy` — the code is
authoritative over the docs here, hence setting it explicitly rather than
omitting it.

**User access:** `jellyfin-k8s` only has the admin account created by its own
setup-Job (matching credentials to `jellyfin-proxy`'s admin). No other real
users exist on it, so `auto_create_users_on_login` (upstream default `true`,
left as-is) won't auto-link anyone else — only the admin account can
authenticate against both backends through jellyswarrm.

## Benchmark scope

Per the direct-play + API-latency scope decided for this comparison: skip
transcode entirely (`jellyfin-k8s` has no GPU passthrough inside the Talos VM
guest, so it would lose that comparison for hardware reasons, not
virtualization ones). Compare library scan time, browse/API response latency,
and direct-play startup/throughput through jellyswarrm to both backends.
