# jellyswarrm (media)

Federation reverse-proxy in front of multiple Jellyfin backends
([LLukas22/Jellyswarrm](https://github.com/LLukas22/Jellyswarrm)), deployed to
compare the host-native `jellyfin-proxy` instance against the in-cluster
`jellyfin-k8s` instance for performance.

- **Enabled:** prod only (`platypod-sops`'s `clusters/prd/secrets.enc.yaml` → `jellyswarrm.enable`).
- **Image:** `ghcr.io/llukas22/jellyswarrm:latest`, port 3000.
- **Hostname:** its own, label-derived (`jellyswarrm.<domain>`) — **not**
  `jellyfin.<domain>`. It briefly hardcoded a hijack of the `jellyfin.<domain>`
  hostname so it would front the real backend transparently for real users;
  reverted after a production incident (see below). No Authelia middleware on
  its `IngressRoute` — it does its own auth (`JELLYSWARRM_USERNAME/PASSWORD`),
  same "own auth, bypass ingress" pattern as Jellyfin/Jellyseerr.
- **Storage:** local `config` volume (`storage.defaultVolumes.config`, subPath
  `jellyswarrm`) for its sqlite db.

## Incident: broke a real user's session (2026-07-02)

`jellyswarrm` briefly owned `jellyfin.<domain>` (the hostname real users and
their apps already pointed at) so the comparison could run with zero visible
change. It broke real usage instead: user `reivi` logged in fine (auto-mapped
to `jellyfin-proxy` via `auto_create_users_on_login`, exactly as designed),
but subsequent requests started failing — most tellingly a `401 Unauthorized`
on the "Continue Watching" query (`/Items?...Filters=IsPlayed`), i.e. "can't
read anything." jellyswarrm's own logs showed:

```
WARN jellyswarrm_proxy::user_authorization_service: Failed to decrypt password for mapping 5. Assuming plaintext.
WARN jellyswarrm_proxy::handlers::users: Authentication failed for server 'jellyfin-proxy' with status: 401 Unauthorized
WARN jellyswarrm_proxy::handlers::users: All authentication attempts failed for user: Reivi
```

She was hitting jellyswarrm from multiple clients (Firefox, Moonfin iOS,
Safari) under inconsistent username casing (`reivi` vs `Reivi`), and each
appeared to race on the same stored server-mapping row — a bug in
jellyswarrm's own session/credential handling, not a misconfiguration on our
side. The real backend (`jellyfin-proxy`) was unaffected throughout; this was
purely jellyswarrm's intermediation breaking.

**Fix applied:** stopped routing real traffic through it. `jellyfin`'s label
was reverted (no more `jellyfin-proxy` rename — it's just `jellyfin` again,
reachable directly at `jellyfin.<domain>` exactly as before any of this), and
jellyswarrm moved to its own dedicated hostname. It stays fully deployed and
usable for the benchmark itself; it's just no longer in the path of anyone's
daily use. **Don't re-attempt the hostname takeover without first
understanding/fixing the multi-client session race upstream.**

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
setup-Job (matching credentials to `jellyfin-proxy`'s admin), so nobody gets
auto-mapped to *that* backend by accident. But `auto_create_users_on_login`
(upstream default `true`, left as-is) very much DOES auto-map any real
`jellyfin-proxy` user who logs into jellyswarrm with their existing
credentials — that's what happened to `reivi` (see incident above). This
setting is about which *servers* a login can auto-map to, not a real access
restriction; it did exactly what it says. The actual mitigation here is
keeping jellyswarrm off real users' path entirely (own hostname), not this
setting.

## Benchmark scope

Per the direct-play + API-latency scope decided for this comparison: skip
transcode entirely (`jellyfin-k8s` has no GPU passthrough inside the Talos VM
guest, so it would lose that comparison for hardware reasons, not
virtualization ones). Compare library scan time, browse/API response latency,
and direct-play startup/throughput through jellyswarrm to both backends.
