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
game traffic over **UDP 8211** (game port) and **UDP 27015** (Steam query) via a
MetalLB **LoadBalancer** service — these ports cannot go through Traefik. There
is no HTTP ingress. Configure `palworld.loadBalancerIP` per-env to a free MetalLB
IP, then open those ports on the router/firewall if public access is needed.

Server settings (`name`, `password`, `adminPassword`, `maxPlayers`, …) live in
`values/default/games/palworld.yaml` and can be overridden per-env in
`values/<env>/values.yaml`.


Static idle game, any authenticated user (`one_factor`). No backend, no state to
preserve.

## Sphaze

3D maze wrapped onto the interior surface of a sphere (Haxe + Heaps, WebGL), any
authenticated user (`one_factor`). Static build served by nginx — no backend, no
state to preserve, same shape as PokéClicker. Image published by
[`platypod/sphaze`](https://github.com/platypod/sphaze)'s own tag-triggered
GitHub Actions workflow; see that repo's README for the release process and the
one-time GHCR package-visibility step required after the first tag.
