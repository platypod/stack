# jellyfin LDAP + Moonfin (media)

Jellyfin authenticates against [lldap](../security/lldap.md) via the community
**LDAP-Auth** plugin, and ships the **Moonfin** (Moonbase) plugin for the
[Moonfin client apps](https://moonfin.io). `media`-group members auto-provision
and can log in with their LLDAP password; `admins`-group members are
auto-promoted to Jellyfin Administrator. The pre-existing local admin account
(`jellyfin.credentials`) is left in place as a non-LDAP break-glass login.

## dev — fully automated

`jellyfin-plugins-setup` (post-install/upgrade hook, weight 20, after
`jellyfin-setup`'s admin bootstrap at weight 10):

1. Installs **LDAP-Auth** (guid `958aad66-3784-4d2a-b89a-a7b6fab6e25c`, official
   repo — no repo registration needed) pinned to `jellyfin.ldap.pluginVersion`.
2. Registers Moonfin's repo (`jellyfin.moonfin.repositoryUrl`) and installs the
   **Moonfin** plugin (its `/Plugins` display name — NOT "Moonbase", despite the
   GitHub repo being `Moonfin-Client/Plugin`).
3. `POST /System/Restart` if anything was installed (plugin assemblies only load
   after a restart) — the official image is PID 1, so the container restarts in
   place under the Deployment's default `restartPolicy`; the Job re-polls/re-auths.
4. Pushes LDAP-Auth config unconditionally every run (config drift self-heals on
   redeploy even when the plugin was already installed): bind as `jellyfin-ldap`
   (read-only, member of `lldap_strict_readonly` — see [lldap.md](../security/lldap.md)),
   search filter scoped to `jellyfin.ldap.userGroup` (`media`), admin filter scoped
   to `jellyfin.ldap.adminGroup` (`admins`), `CreateUsersFromLdap: true`, `uid` as
   the username/uid attribute (LLDAP convention).
5. Seeds libraries from `jellyfin.libraries` via `POST /Library/VirtualFolders`.
   An init container `mkdir -p`s every configured path first — Jellyfin's API
   rejects library paths that don't exist on disk, and dev's media PVC starts
   empty. **`jellyfin.libraries` ships with placeholder paths
   (`/media/movies`, `/media/tv`) — replace with the real NFS subfolder layout
   before this matters for real content.**

Requires `jellyfin.pvc.media` (read-only NFS mount at `/media`, added alongside
`pvc.config` — previously `jellyfin.pvc` was config-only).

Known risk to watch: [ldapauth#224](https://github.com/jellyfin/jellyfin-plugin-ldapauth/issues/224)
reports LDAP admin-sync instability / config resets on Jellyfin 10.11.10 +
plugin 23.0.0.0 (the pinned version here, against `jellyfin.image: 10.11.11`) —
hasn't reproduced in testing, but re-check before bumping either pin.

## prod — manual, host-native (out of automation's reach)

Prod's `jellyfin` release is `inCluster: false` — a Traefik proxy in front of
the **real** Jellyfin, which runs host-native on mini4 (GPU transcode via
VideoToolbox, outside this repo entirely). None of the in-cluster
`jellyfin-plugins-setup` automation runs there; the plugin has to be installed
and configured by hand in the admin dashboard
(`https://jellyfin.platypod.ovh/web/` → Dashboard → Plugins).

### LDAPS via Traefik (not a raw exposed port)

mini4 can't reach LLDAP's ClusterIP at all — it's a hypervisor host running the
Talos VM as a guest (same as dev's laptop), with zero route into the cluster's
pod/service network. Rather than exposing plaintext LDAP on the LAN
(`externalIPs`, the same mechanism `traefik.externalIP`/`adguard.externalIP`
use), LLDAP is fronted through **Traefik's own TLS**, on a dedicated TCP
entrypoint:

- `traefik.ports.ldaps` (`:636`) — a **TCP** entrypoint, not HTTP. Every other
  service here is multiplexed on `:443` via HTTP-layer `Host()` routing, which
  only works because the traffic *is* HTTP after TLS termination. Raw LDAP(S)
  isn't HTTP (no `Host()` header to route on), so it needs Traefik's separate
  `IngressRouteTCP` router type, which needs its own entrypoint. Sharing `:443`
  via SNI-based TCP/HTTP muxing is possible but adds routing-precedence
  complexity to the single most critical path in the stack; a dedicated port is
  isolated by construction — misconfiguring it can't affect anything else.
- `lldap.ldaps.enable` (prod only) → `lldap--ingress-route-tcp.yaml`:
  `IngressRouteTCP` on entrypoint `ldaps`, `HostSNI(`*`)` (the entrypoint
  carries no other traffic), `tls.store: default` (the same trusted LE wildcard
  cert as everything else — **no `SkipSslVerify`, no `UseStartTls`**, real TLS).
  Terminates at Traefik; forwards **plaintext** to `lldap:3890` inside the
  cluster — same edge-TLS/plaintext-inside pattern as every HTTPS-fronted app
  here. LLDAP itself needs zero TLS config.
- Prod-only bind account `jellyfin-ldap` lives in `values/prd/values.yaml`'s
  `lldap.seed.users` (NFS-stored, not in git — prod's seed list fully
  **overrides** the default one, so it has to be added there specifically, not
  just in `values/default`).

### DNS gotcha — mini4 needs a hosts-file override

mini4's system resolver is the ISP/router, not AdGuard, so
`lldap.platypod.ovh` resolves to the **public** WAN IP there instead of
`192.168.1.156` (chuwi-cp1, where the `ldaps` entrypoint answers). Same class
of gap as `k8s.platypod.lan` — fixed the same way, a break-glass
`/etc/hosts` line on the affected host:
```
192.168.1.156  lldap.platypod.ovh
```

### macOS Local Network permission — the actual cause of intermittent login failures

**This, not a flaky-network theory, is the real root cause** of LDAP logins
failing with `SocketException 65: No route to host 192.168.1.156:636` from
Jellyfin's own process, while the exact same connection succeeds from any other
tool on the same machine at the same time.

Since macOS Big Sur, an app must hold the **Local Network** privacy permission
(System Settings → Privacy & Security → Local Network) before it can *initiate*
an outbound connection to another device on the LAN (inbound connections and
internet-bound traffic don't need it). This was the first time Jellyfin had
ever needed to reach another LAN device — everything else it does is internet
traffic, localhost, or serving inbound connections — so it had never been
granted the permission, and had no reason to hold it before.

**Diagnosis** (don't guess — check these two things):
- `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT service, client, auth_value FROM access WHERE service='kTCCServiceLocalNetwork';"`
  — no row for the app's bundle id means it's never been granted.
- `log show --predicate 'eventMessage contains[c] "LocalNetwork"'` around the
  failure timestamp shows `UserEventAgent [com.apple.networkextension:]
  LocalNetwork: found bundle id <name> by PID` at the exact moment of each
  failed connection — confirms this permission check is what's intercepting it.

**Fix**: System Settings → Privacy & Security → Local Network → grant the app.
If it's not listed yet, launch it normally (GUI, not headless) once so macOS
shows the permission prompt — the grant is per-bundle-id and persists
regardless of how it's launched afterward (including via the LaunchAgent
below).

This is SIP-protected; there's no way to grant it non-interactively.

### Jellyfin process supervision — `org.platypod.jellyfin` LaunchAgent

Lives only on mini4 (`~/Library/LaunchAgents/org.platypod.jellyfin.plist`) —
**not in this repo**, host-level macOS config outside Helm/Terraform's reach.
Replaces the previous Login Item (removed, to avoid a double-launch at next
boot). `RunAtLoad` + `KeepAlive`.

- **LaunchAgent, not LaunchDaemon, deliberately.** A LaunchDaemon runs as root
  with no GUI/WindowServer session — VideoToolbox hardware transcode access has
  historically been unreliable without one, and hardware transcode is this
  host's entire reason for being host-native instead of in-cluster. A
  LaunchAgent preserves the same per-user GUI-session execution model the app
  already used successfully.
- `KeepAlive: true` means quitting from the menu bar no longer actually stops
  it — launchd relaunches it. To deliberately stop it:
  `launchctl bootout gui/501/org.platypod.jellyfin`.
- Protects against the process dying outright (crash, kill). It does **not**
  protect against — and would not have caught — a bug where the process stays
  alive but individual requests start failing (see next section); that class
  of issue still needs a manual restart.

### File Transformation plugin — crashed `/web/` for everyone (2026-08-18)

Unrelated to LDAP, found and fixed in passing. The **File Transformation**
plugin (installed for Moonfin's optional "Moonfin button" in the web header —
see [Moonfin's install docs](https://github.com/Moonfin-Client/Plugin)) threw
`System.ObjectDisposedException: Cannot access a disposed object. Object name:
'IServiceProvider'` inside its `RegisterTransformation` hook on every single
`/web/` request, taking down the web UI for the whole household while the API
itself stayed healthy. Disabling the plugin alone didn't fix it — the crashed
hook stays registered in the running process regardless of the "enabled" flag;
it needed an actual process restart to unload. Currently **disabled** on prod.
Re-enable only after confirming a fixed version, if the Moonfin-button feature
is wanted.

## Values reference

| Value | Default | Purpose |
|---|---|---|
| `jellyfin.pvc.media` | `storage.defaultVolumes.media` | Read-only NFS mount at `/media` (dev only — prod is host-native) |
| `jellyfin.libraries` | placeholder movies/tv | Seeded via `VirtualFolders`; **replace paths before relying on it** |
| `jellyfin.ldap.*` | see [jellyfin.yaml](../../values/default/media/jellyfin.yaml) | Plugin version pin, bind account, group filters |
| `jellyfin.moonfin.*` | see same file | Repo URL, enable flag |
| `lldap.ldaps.enable` | `false` (`true` in prod) | Gates the `IngressRouteTCP` |
| `traefik.ports.ldaps` | `:636` | Dedicated TCP entrypoint, always present (cheap; only routed when `lldap.ldaps.enable`) |
