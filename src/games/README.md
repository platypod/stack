# games module

## RomM

ROM library manager (`group:media`), backed by its own **MariaDB** (`rommapp-db`).
Delegates login to Authelia via **OIDC** with account provisioning on first login.
ROM files live on the media NFS share.

> **Version bumps need care.** RomM's Alembic migrations use MariaDB
> `batch_alter_table`, which silently drops `if_exists`/`if_not_exists` guards — a
> half-applied migration crash-loops the pod. The migration path from a clean DB
> is reliable; in-place upgrades across several minor versions are not. On prod,
> bump the image and let the operator handle the base migration manually (ROM
> files on NFS are never touched).

## Palworld

Dedicated Palworld game server (`thijsvanloef/palworld-server-docker`). Exposes
game traffic over **UDP 8211** (game port) and **UDP 27015** (Steam query) —
these ports cannot go through Traefik (HTTP-only). There is no HTTP ingress.

Dev has MetalLB: set `palworld.loadBalancerIP` to a free pool IP. Prod has no
MetalLB — set `palworld.externalIP` (shares `chuwi-cp1`'s LAN IP with
Traefik/AdGuard) and `palworld.nodeSelector` to pin it there; see
`traefik.externalIP` in `values/default/core/traefik.yaml` for the mechanism.
Open the ports on the router/firewall if public access is needed.

Server settings (`name`, `password`, `adminPassword`, `maxPlayers`, …) live in
`values/default/games/palworld.yaml` and can be overridden per-env in
`values/<env>/values.yaml`. Anything else the image exposes — the full table
is at [palworld-server-docker.loef.dev](https://palworld-server-docker.loef.dev/),
including the actual `PalWorldSettings.ini`-mapped gameplay/difficulty/drop-rate
keys — drops straight into `palworld.server.extraEnv` as a plain key/value map,
with no chart change needed per setting (e.g. `DEATH_PENALTY: "None"`,
`DIFFICULTY: "Difficult"`). Note `MULTITHREADING` is deprecated by the image in
favor of `ENABLE_PERF_THREADING_ARGS` (wired as `palworld.server.perfThreadingArgs`)
plus an optional `WORKER_THREADS_SERVER` thread count via `extraEnv`.

**Memory sizing:** the image's own docs state 16GB minimum / 32GB+
recommended — well above what a first guess might assume for a small
multiplayer server. `palworld.resources` defaults conservatively (`4Gi`/`8Gi`,
safe for a resource-constrained dev worker) but prod overrides it to
`16Gi`/`32Gi` in `values/prd/values.yaml`, matching the real recommendation —
`chuwi-cp1` has ample headroom for it (as of 2026-07-31: ~61Gi allocatable,
~14% requested). Re-check `kubectl describe node chuwi-cp1`'s "Allocated
resources" before enabling more game workloads there, since everything in this
module that needs external exposure ends up sharing that one node (see
Minecraft below).

## Minecraft

Zero or more named instances (vanilla, CurseForge modpacks) under
`minecraft.instances` in `values/default/games/minecraft.yaml` — each is its
own `itzg/minecraft-server` Deployment + **ClusterIP-only** Service (never
exposed directly), keyed by name (e.g. `vanilla`, `bcgplus`, `cobbleverse`).
Enable any subset simultaneously with `minecraft.instances.<name>.enable`.

**Why ClusterIP + a router in front, instead of exposing each instance like
Palworld:** Minecraft's protocol is plain, unencrypted TCP — no HTTP `Host`
header, no TLS SNI — so Traefik has no field to route on, and giving every
instance its own externalIP/port doesn't scale with "several packs at once."
`itzg/mc-router` solves this: it peeks at the hostname inside Minecraft's own
handshake packet and proxies to the right backend, so every instance can share
one port (`25565`) under its own subdomain. It runs in `--in-kube-cluster`
mode with `KUBE_NAMESPACE` set, watching for Services (via the RBAC in
`mc-router--rbac.yaml`, not DNS) carrying the
`mc-router.itzg.me/externalServerName` annotation — enabling/disabling an
instance changes routing automatically, nothing to edit on mc-router's side.
RBAC is a **ClusterRole**, not a namespaced Role: despite `KUBE_NAMESPACE`,
mc-router 1.23.0's informer still issues a cluster-scope List/Watch on
Services (confirmed live — a namespaced Role fails with "services is
forbidden ... at the cluster scope"), matching upstream's own example
manifests. Read-only on Services, cluster-wide. mc-router's own Service is the only one
that needs `mcRouter.externalIP`/`nodeSelector` (prod, pinned to `chuwi-cp1`,
same externalIPs mechanism as Palworld) or `mcRouter.loadBalancerIP` (dev).
Only rendered at all once at least one instance is enabled.

Each instance's world data lives on the shared `apps` PVC under
`minecraft/<label from hostname>/`, so instance pods themselves carry no
node affinity and can run on any node with room — unlike mc-router, which
must colocate with the shared externalIP.

CurseForge modpacks (`type: AUTO_CURSEFORGE`) need a pinned `slug`/`fileId`
per instance. **`minecraft.curseforge.apiKey` is optional, not required** —
despite CurseForge locking down its API in 2023, the `itzg/minecraft-server`
image now ships a bundled default key, so `AUTO_CURSEFORGE` works with zero
CurseForge account. Only set `curseforge.apiKey` if downloads start failing
under shared-key rate limits. Match each instance's `image` tag's Java version
to its modpack's actual Minecraft version — e.g. MC 1.20.1 needs Java 17, MC
26.2 needs Java 25 (LTS) — the image is pinned per-instance for exactly this
reason, not shared.

**Minecraft versioning changed in 2026.** Mojang moved off the `1.21.x` line
to year-based versions (`26.1`, `26.2`, `26.3`, …), shipped as a few named
"drops" a year rather than a change in update cadence. `1.21.11` etc. show up
on the wiki as internal data/feature-format labels some third-party tooling
(Paper/Spigot builds) still surfaces, not real standalone Mojang releases —
don't set `version:` to one of those for `TYPE: VANILLA`. Current stable is
`26.2` ("Chaos Cubed", 2026-06-16); `26.3` was in snapshot testing as of
2026-07-31, not yet a full release.

Any other itzg/minecraft-server env var — e.g. `PAUSE_WHEN_EMPTY_SECONDS` (see
below) — drops into `minecraft.instances.<name>.extraEnv`, same mechanism as
Palworld's.

**Auto-pause is normal, not a bug.** Vanilla servers on MC 1.21.2+ (so 26.2)
log `Server empty for 60 seconds, pausing` and suspend the tick loop while
idle — the network listener stays up, and a new connection attempt resumes it.
Nothing to do about it; tune the idle threshold via `PAUSE_WHEN_EMPTY_SECONDS`
in `extraEnv` if 60s is wrong for your use case.

**Connect using the instance's own hostname, not a generic `minecraft.<domain>`.**
mc-router only knows the exact hostnames registered via the
`mc-router.itzg.me/externalServerName` annotation (i.e. each instance's
`hostname` value) — anything else logs `Unable to find registered backend` and
is rejected. There's no catch-all/default instance configured.

Public DNS (or AdGuard rewrites, dev) needs a real record per enabled instance
hostname — that's what puts the right string in the client's handshake for
mc-router to read, it's unrelated to how mc-router finds the backend Service.
In prod, AdGuard's existing `*.<traefik.domain>` wildcard rewrite (see
`traefik.externalIP`) already covers any instance hostname automatically for
LAN clients using AdGuard as their resolver — internet-facing access still
needs a real public DNS record plus a router port-forward for TCP `25565` to
`mcRouter.externalIP`, neither of which this chart can do for you.

## PokéClicker

Static idle game, any authenticated user (`one_factor`). No backend, no state to
preserve.

## Sphaze

3D maze wrapped onto the interior surface of a sphere (Haxe + Heaps, WebGL), any
authenticated user (`one_factor`). Static build served by nginx — no backend, no
state to preserve, same shape as PokéClicker. Image published by
[`platypod/sphaze`](https://github.com/platypod/sphaze)'s own tag-triggered
GitHub Actions workflow; see that repo's README for the release process and the
one-time GHCR package-visibility step required after the first tag.
