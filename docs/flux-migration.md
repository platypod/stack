# Flux migration (plan)

> **Status: Phases 0-5 and 7-8 done — prod cut over onto Flux, all 8 releases
> adopted in place and `v1.0.0`-tagged, Helmfile fully decommissioned; Phase 6
> retired (merged into Phase 3); only Phase 9 (deferred image automation)
> remains.** It records the decisions (with rejected alternatives)
> and the phased path from today's Helmfile + `make` workflow to Flux CD
> across three clusters. Conventions live in [conventions.md](conventions.md);
> day-to-day operations in [operations.md](operations.md); other stack
> decisions in [decisions.md](decisions.md).

## What changes, and why

Today the stack is deployed **imperatively**: `make deploy [MODULE=] [ENV=]` runs
`helmfile sync` from a laptop holding the kubeconfig. Nothing detects drift, and
the env values (including all prod secrets) live **outside Git** — gitignored,
with `values/prd/values.yaml` a symlink to the Synology share
([../../infra/docs/secrets-on-nfs.md](../../infra/docs/secrets-on-nfs.md)).

Flux inverts this: controllers *inside* each cluster reconcile from Git. The
motivating gains are credential-free auto-deploy of the custom GHCR images (the
question left open in `sphaze`'s README), drift correction, and Git as the single
source of truth. The forcing constraint is that **Flux can only deploy what is in
Git**, so moving the env values into Git under SOPS is a precondition, not
an optional cleanup — see the SOPS decision below for why that's a second,
private repo rather than `platypod/stack` itself.

## Decisions

### Flux-native `HelmRelease`, not Helmfile-as-renderer

The 8 module charts are reconciled as `HelmRelease` objects by `helm-controller`,
sourced from a `GitRepository` pointing at this repo (`chart: ./src/<module>`).
Helmfile is retired once prod is cut over.

Rejected: **Helmfile-as-renderer** (`helmfile template` → commit rendered YAML →
Flux applies) — keeps two mental models for one deployment and loses Helm release
semantics; **image-automation-only** (add `image-reflector`/`image-automation`
beside the existing Helmfile flow) — solves auto-deploy but none of the drift,
secrets, or source-of-truth problems, and would have to be redone later anyway.

### One branch, directory per cluster, prod pinned to a tag

A single `main` branch. Each cluster runs its own Flux with its own
`GitRepository` ref and its own path:

| Cluster | `spec.ref` | Path | Behaviour |
|---|---|---|---|
| local | `branch: main` | `clusters/local` | reconciles HEAD — scratchpad |
| dev | `branch: main` | `clusters/dev` | reconciles HEAD — rehearsal |
| prd | `semver: ">=1.0.0"` | `clusters/prd` | **moves only on a new tag** |

Promotion is `git tag vX.Y.Z && git push --tags`; rollback is re-pointing to the
previous tag. Env-specific config lives under `clusters/<env>/`, so editing one
cluster's overlay cannot affect another. Changes to shared `apps/base/` reach
local and dev immediately, and prod only when tagged — which is precisely the
promotion gate.

Rejected: **branch per cluster** (the original sketch) — with three clusters it
creates a three-way backport matrix where any prod-only hotfix is silently
reverted by the next forward-merge. The "test before prod" property it was meant
to buy is delivered better by the source ref, without divergence.

### Three-tier values model, split by role rather than by module

Measured over the original 62 tracked files in `values/default/`: `k8s` was
consumed by 47, `traefik` by 46, `storage` by 37, while `authelia.yaml`
referenced **38** top-level keys and `uptime-kuma.yaml` **28**, spanning
every module. Those two aggregators made purely chart-local values
impossible — but only service *identity* is genuinely shared, not service
*implementation*:

| Tier | ConfigMap/Secret (Flux era) | Contents | Fed to |
|---|---|---|---|
| Substrate | `platypod-globals` (ConfigMap) | `project`, `k8s`, `traefik`, `storage`, `acme`, `priority` | all 8 releases |
| Registry | `platypod-services` (ConfigMap) | per service: `enable`, `label`, `host` | all 8 releases |
| Implementation | `platypod-<module>` (ConfigMap) | `image`, `resources`, `ports`, service config | that module only |
| Secrets | `platypod-secrets` (**Secret**, generated from `platypod-sops` via SOPS + `secretGenerator` — see below) | credentials | releases needing them |
| Env override | `platypod-env-*` (ConfigMap) | per-cluster deltas | all 8 releases |

**Implemented (Phase 2, done):** `values/default/` is now 9 files —
`substrate.yaml`, `registry.yaml`, and one implementation file per module
with content (`core.yaml`, `dev-tools.yaml`, `files.yaml`, `games.yaml`,
`media.yaml`, `observability.yaml`, `security.yaml`; `persistence` has none
of its own — its only default file, `storage.yaml`, is pure substrate).
Two nuances the original sketch above didn't capture, found while doing the
actual split: some top-level keys aren't per-service at all and don't fit
the registry/implementation split cleanly — `media.system` (module-wide
paths) and `security.accessGroups` (shared LDAP group definitions) stay
wholly in their module's implementation file. And not every registry-eligible
service has all three fields — several game servers (`palworld`, `valheim`,
`terraria`, `satisfactory`) are LAN services with no `host` (no Traefik
routing), so their registry entries carry only `enable`/`label`.

The "~5 `valuesFrom` entries instead of 56" outcome is a **Flux-era** claim —
under today's Helmfile, `values:` is still one list per release regardless
of file count, so the 62→9 file consolidation doesn't itself shrink anything
Helmfile-side; the payoff lands once Phase 4's `configMapGenerator` wraps
each of these 9 files into one ConfigMap per tier and `HelmRelease.valuesFrom`
references those instead of listing files directly. Doing the consolidation
now, under Helmfile, was about using golden-manifest diffing as the safety
net while it's cheap (see Phase 2 below) — not an immediate Helmfile
optimization.

`host` values stay literal template strings resolved by `tpl` inside the
charts — unchanged, since all tiers deep-merge into one `.Values` before Helm
renders.

Rejected: **lift-and-shift** (one ConfigMap per existing file, fanned out via a
Kustomize component + JSON6902 patch) — preserves the "every release sees
everything" problem and adds a brittle 56-entry patch; **fully chart-local
defaults** (move values into each chart's `values.yaml`, which no chart currently
has) — cannot satisfy authelia/uptime-kuma without a global registry anyway.

### SOPS + age in a second, private repo; NFS unchanged for infra

Env values move into Git encrypted with SOPS + age — but into a **second,
private repo**, [`platypod/platypod-sops`](https://github.com/platypod/platypod-sops),
not `platypod/stack` itself.
`platypod/stack` stays fully public (charts, docs, non-secret values,
unchanged); `platypod-sops` holds every secret value, still SOPS+age-encrypted
*inside* the private repo — defense in depth against a leaked deploy key or an
accidental repo-visibility flip, not reliance on privacy alone.

One file format across both eras of the migration: plain Helm values YAML,
SOPS-encrypted whole-file — never pre-rendered Kubernetes `Secret` manifests,
so the same encrypted files work unchanged whether they're consumed by
Helmfile (Phases 1-2) or Flux (Phase 3+).

**Phases 1-2 (Helmfile):** `platypod-sops` is added as a git submodule of the
top-level `platypod` meta-repo — the same pattern already used for `infra`,
`mediarvester`, etc. (`stack/Makefile` already reaches across to `../infra`
for the kubeconfig path, so `../platypod-sops` from within `stack/` is a
natural extension).

**Implemented (Phase 1, dev-only — see below), with one mechanism
correction:** the plan below originally called for helmfile's native
`secrets:` stanza (which shells out to the `helm-secrets` Helm plugin to
decrypt). That plugin is currently broken on Helm v4 — Helm v4's plugin
loader classifies any legacy plugin that also declares `downloaders:` (needed
for SOPS URL-scheme support) as a pure "getter" plugin and drops its `helm
secrets <cmd>` CLI registration entirely, so `helmfile ... diff` fails with
`unknown command "secrets" for "helm"` regardless of which `helm-secrets`
version is installed. No upstream fix as of this writing. Worked around by
bypassing the plugin: `make decrypt-secrets` (a prerequisite of
`diff`/`deploy`/`deploy-base`) calls the `sops` binary directly, decrypting
`../platypod-sops/stack/<env>/secrets.enc.yaml` into a gitignored
`tmp/secrets/<env>.yaml`, which `helmfile.yaml.gotmpl` then reads as a plain
`values:` entry — same encrypted-file format as originally planned, just a
different decrypt mechanism. `dev`'s `values:` list and its `environments:`
block are wired this way; `prd` is untouched, still on its NFS-linked
`values/prd/values.yaml` — a deliberate scope cut (prove the mechanism on
dev first), tracked as a follow-up. The template carries a temporary
`.Environment.Name == "dev"` branch for this split, collapsing back to one
code path once `prd` migrates too.

**Phase 3+ (Flux):** each cluster gets **two** `GitRepository` sources —
`stack` (public, existing/new deploy key) and `platypod-sops` (private, a
**separate** read-only deploy key). A `Kustomization` sourced from the
`platypod-sops` `GitRepository` (`spec.decryption.provider: sops`) decrypts
`secrets.enc.yaml` in-memory, then a Kustomize `secretGenerator` wraps the
decrypted content into a real in-cluster `Secret`, which the "Secrets" tier's
`HelmRelease.spec.valuesFrom` entries reference by name — same shape as the
ConfigMap-based tiers, just backed by a generated Secret from a second
source.

The age private key itself is unaffected by the repo split: created
out-of-band, never committed to either repo, referenced in-cluster as
`flux-system/sops-age`, backed up on the existing NFS share.
`Kustomization.spec.decryption` decrypts at apply time. Infra's
`terraform.tfstate` / `prod.tfvars` stay on NFS exactly as today — infra and
stack intentionally use different secret models, because only the stack needs
to be readable by an in-cluster controller.

This keeps the standing constraint intact: the credential that leaves the
machine is a **GitHub deploy key stored in the cluster**, never a cluster
credential stored at GitHub — now true for two deploy keys instead of one.

**Prod promotion stays lockstep across both repos.** Tagging a prod release
means tagging `platypod/stack` and `platypod-sops` at the identical `vX.Y.Z`
— one promotion gate, unambiguous rollback (re-point both refs to the same
prior tag), at the cost of needing a tag even for a pure secret rotation.
`prd`'s `GitRepository.spec.ref` for both repos uses the same
`semver: ">=1.0.0"` constraint. Worth a small `make release VERSION=vX.Y.Z`
wrapper later that tags+pushes both as one operation — not built yet.

Rejected: **single-repo SOPS** (the original sketch — encrypt in place inside
`platypod/stack`) — works, but mixes a public repo's casual-clone audience
with secret material even encrypted, and blocks ever making `stack` fully
public-contributable; **recursing `platypod-sops` as a git submodule *inside*
`platypod/stack`**, letting Flux's single `GitRepository` for `stack` pull it
in via `spec.recurseSubmodules: true` — rejected because submodule recursion
needs its own credential resolution for the nested remote, which a single
`GitRepository.spec.secretRef` doesn't cleanly cover for a *different* repo
with *different* auth, and it re-couples the two repos' checkout lifecycle (a
stack-only reconcile would refetch sops content it didn't need to); **SOPS-
encrypted `Secret` manifests directly in `platypod-sops`** (skip the
`secretGenerator` indirection, commit actual `kind: Secret` YAML with just
`data`/`stringData` encrypted) — works for Flux but has no equivalent for
Helmfile's `secrets:` stanza, which expects plain Helm values files; would
mean re-authoring every secret's format when Flux takes over; **independent
tags per repo** — more flexible for a pure secret rotation, but two moving
promotion gates and manual tag-compatibility bookkeeping on rollback;
**keeping values on NFS** — Flux cannot follow a laptop symlink; **external
secrets operator** — a second standing service for a problem SOPS solves with
a file.

### Dev on `*.dev.platypod.ovh`, WAN via port 8443

`platypod.ovh` is retained for prod. Dev takes the `dev.` subdomain, issued via
the **same OVH DNS-01 credential** — note a `*.platypod.ovh` wildcard does *not*
cover `*.dev.platypod.ovh` (wildcards match exactly one label), so dev needs its
own wildcard cert. DNS-01 needs no inbound connectivity, so dev can be stood up
with browser-trusted certs before WAN routing is solved.

The `k8s.names.urls.suffix` mechanism already present in
`values/dev/values-template.yaml` (`suffix: .${project.env}`) produces
`jellyfin.dev.platypod.ovh` with no template changes. It is currently disabled on
the laptop with the comment *"single-level so the wildcard cert matches"* — an
mkcert limitation that no longer applies once dev has a real per-env wildcard.

WAN reach: the router forwards **8443 → dev-machine:443**. Local keeps
`*.platypod.local` with mkcert and `traefik.tls.selfSigned: true`.

Rejected: **SNI demux on prod's Traefik** (`IngressRouteTCP` with TLS passthrough
matching `HostSNIRegexp`) — clean URLs and no router change, but makes dev's WAN
reachability depend on prod's Traefik, i.e. breaking prod removes WAN access to
the cluster you would use to rehearse the fix; **IPv6 address per cluster** —
architecturally cleanest, but leaves dev unreachable from IPv4-only networks;
**a separate domain** — extra cost and DNS config for no gain over a subdomain;
**nginx stream demux in front** — would require moving Traefik off 443 on chuwi,
re-inserting a hop the bare-metal migration removed.

**Consequence to implement:** a non-default external port must appear in
generated URLs. `src/security/templates/authelia/authelia--config-map.yaml` has
**22** hardcoded `https://{{ tpl .Values.X.host . }}/…` redirect URIs (not 23
— corrected while doing Phase 2's file split, which required reading every
one), plus `wikijs.oidc.redirectUri` (now in `values/default/dev-tools.yaml`).
All need a port segment or OIDC breaks on dev. Add a `k8s.names.urls.port`
global (empty for prod/local, `:8443` for dev) and thread it through those 23
sites.

**Implemented (Phase 2, done):** `k8s.names.urls.port` exists in
`values/default/substrate.yaml` (default `""`), threaded through all 23
sites. Not yet set to `:8443` anywhere — that's tied to the WAN-reachable dev
machine, which is blocked on hardware (the intended dev machine, a 2017 Mac
mini, can't run Talos). Verified to render byte-identical to the pre-change
golden manifests for both `dev` and `prd` today, since the port default is
empty for both.

### Flux owns CRDs, the CSI driver, and itself

`make install-crds` and `make install-csi` are replaced by Flux resources, and
Flux manages its own manifests (`flux bootstrap`). Cluster bring-up in `infra/`
gains a bootstrap step.

Rejected: **apps-only scope** (CRDs/CSI stay imperative) — smaller first cut, but
leaves cluster bring-up half-imperative and blocks the "rebuild a cluster from
Git" property that motivates the migration.

## Target layout

```
stack/                           # public repo
  src/                           # 8 Helm charts — UNCHANGED
  clusters/
    {local,dev,prd}/
      flux-system/                # bootstrap-generated, self-managed
      infrastructure.yaml         # Kustomization → infrastructure/*
      apps.yaml                   # Kustomization → apps/
      secrets.yaml                # Kustomization sourced from platypod-sops
      values/{globals,services}.yaml
  infrastructure/
    crds/                        # VENDORED Traefik CRDs (see gotcha 1)
    controllers/                 # csi-driver-nfs HelmRepository + HelmRelease (prd)
  apps/base/
    kustomization.yaml
    kustomizeconfig.yaml         # nameReference for valuesFrom (see gotcha 2)
    helmrelease-*.yaml           # 8, with dependsOn mirroring today's needs:
    values/                      # globals, services, per-module

platypod-sops/                   # private repo, separate deploy key
  stack/
    {dev,prd}/secrets.enc.yaml    # Phases 1-2: consumed by helmfile `secrets:`
  clusters/
    {local,dev,prd}/
      secrets.enc.yaml            # Phase 3+: SOPS, decrypted+wrapped via secretGenerator
```

Reconcile order: `flux-system` → `infra-crds` → `infra-controllers` → `apps`,
via `Kustomization.dependsOn`. Within `apps`, the existing `needs:` graph from
`helmfile.yaml.gotmpl` ports 1:1 to `HelmRelease.spec.dependsOn` — including the
`files` → `media` edge that `CLAUDE.md` flags as the expensive one to get wrong.

## Phases

The safety net throughout is **golden-manifest diffing**: capture
`helmfile --environment <env> template` before any restructuring, and require
byte-identical output after each step that is not meant to change behaviour.

**Phase 0 — rotate the exposed dev/local secrets. Status: done.** `platypod/stack`
is a public repo. `authelia.oidc.hmac_secret` and `lldap.jwtSecret` were real
generated values committed since `c02cc7d` / `d92af24` and never rotated —
`hmac_secret` turned out to be dead/unwired at the time (Authelia silently
fell back to `SHA256("")` for OIDC token signing rather than reading it; wired
in properly by commit `c125189`, at which point it also needed rotating).
Prod overrode both, so prod was never exposed. Fixed: generated per-env
values, replaced the committed values with *obvious* placeholders (matching
the existing `verySecretMuch…` style), added a render-time `fail` guard
keyed on the placeholder value itself (not the env name — sidesteps the
still-unresolved local/dev rename). Also rotated the remaining plaintext
credentials found in the same files while at it (`lldap.adminPassword`, the
`lldap`/`authelia` Postgres sidecar passwords, all 5 seeded LLDAP user
passwords). Blast radius: dev/local sessions invalidated once; prod
untouched throughout (`make diff ENV=prd` stayed clean at every step).

**Phase 1 — SOPS in a second private repo, still on Helmfile. Status: done,
dev only.** Created the `platypod-sops` repo (private, own read-only deploy
key), added it as a git submodule of the top-level `platypod` meta-repo
alongside `infra`/`stack`. Moved `values/dev/values.yaml` into
`platypod-sops/stack/dev/secrets.enc.yaml` encrypted. Mechanism deviated from
the original plan — see the SOPS decision above for why (`helm-secrets` is
broken on Helm v4; `make decrypt-secrets` + a plain `values:` entry stood in
for helmfile's native `secrets:` stanza). `bin/install-deps.sh` gained
`sops`/`age`. `prd` untouched — still on its NFS-linked `values/prd/values.yaml`,
migrating it is a deliberate follow-up once dev has proven the mechanism
further. Gate: `make diff ENV=prd` clean — confirmed at every step.

**Phase 2 — retier the values, still on Helmfile. Status: done.** Reorganised
the 62 default files into the tiers above (9 files); added `k8s.names.urls.port`
and threaded it through the 23 URL sites. Gate: rendered output identical to
the golden manifests at every step (including the port-threading step, since
the port default is empty for both envs today) — confirmed via
`helmfile template` diffing for both `dev` and `prd`, plus `make diff ENV=prd`.

**Phase 3 — Flux on the laptop cluster. Status: done, merged with the old
Phase 6.** Originally planned as two separate phases — bootstrap Flux
greenfield on a *new* dev machine first (zero stakes, discover gotchas
there), only *then* redo it on the laptop (old Phase 6), once proven
elsewhere. The new machine doesn't exist (2017 Mac mini can't run Talos);
per the user's call, merged the two — bootstrapped directly on the laptop's
own cluster instead, accepting that gotchas get found on the cluster used
day-to-day rather than a throwaway (mitigated: it's a disposable vfkit VM
pair, `make destroy && make apply` rebuilds it from scratch).

Bundled in the same rebuild: the `dev`→`local` rename (deferred in Open
Items to "at its next rebuild" — this was that rebuild; see `infra/TODO.md`'s
prod→prd precedent for why a live env can't be renamed in place). Destroyed
the old `dev` VMs, applied fresh as `local`, re-ran the existing bootstrap
sequence (`setup-local-tls`, `install-crds`, `deploy-base`, `setup-local-dns`)
unchanged in shape — proved the rename worked via Helmfile *before* touching
Flux at all. Installed the `flux` CLI, vendored the Traefik CRDs into
`infrastructure/crds/` (gotcha 1), ran `flux bootstrap github` against
`platypod/stack` path `clusters/local` — added one read-only deploy key,
pushed `clusters/local/flux-system/*` directly to `main`. Wired the vendored
CRDs in via a `clusters/local/infrastructure.yaml` `Kustomization`
(`infra-crds`) — `flux get kustomizations` shows both `flux-system` and
`infra-crds` reconciled and healthy. **Scope boundary held**: no app
modules/`HelmRelease`s yet — the existing Helmfile-deployed
persistence/core/security releases kept running throughout, completely
unmanaged by Flux. That's Phase 4.

One deferred step: `setup-local-dns` needs an interactive `sudo` password
prompt (`networksetup`), so it couldn't run non-interactively — the user
needs to run it themselves once, to point this laptop's system DNS at the
new cluster's AdGuard.

**Phase 4 — port the 8 modules to `HelmRelease` on local. Status: done.** All
8 (`persistence`, `core`, `security`, `observability`, `dev-tools`, `media`,
`games`, `files`) ported, adopted in place, and healthy — same
`dependsOn` graph as `helmfile.yaml.gotmpl`'s `needs:`, `files` correctly
waiting on `media`. `apps/base/` carries the two-tier `configMapGenerator`
set (substrate + registry + 7 per-module) plus all 8 `HelmRelease`s; every
release gets all 7 module ConfigMaps (not just its own — see gotcha 2), the
`platypod-sops` Secret, and `reconcileStrategy: Revision` (gotcha 8).

Found and fixed four new issues beyond the original gotcha list while
getting `observability` and `files` to actually go healthy (gotchas 8-11
below): stale chart packaging, a `chartVersion` label that broke under
Flux's revision suffix, two `local`-only resource-capacity walls
(loki/otel-gateway, otel-collector's control-plane DaemonSet replica), and
a real bug in both `files` setup Jobs (`torrent-clients-setup`,
`sabnzbd-setup`) that unconditionally polled *arr apps regardless of their
own `enable` flag — harmless on prod (everything enabled there) but a
15-minute-per-disabled-app hang on `local`, where Sonarr/Radarr/Readarr/
Prowlarr are deliberately off (undersized node). Also corrected an earlier
wrong claim about the `prometheus-snmp-exporters` duplicate-IngressRoute
bug (see gotcha 9) — it does not distinguish `local` from prod as cleanly
as first thought.

Deferred, not yet scripted as a Make target (same reproducibility gap
flagged after Phase 3 for the in-cluster `platypod-sops` deploy key): the
per-module `helmrelease-*.yaml` authoring itself was manual (one-time,
not re-run on every rebuild, so lower priority than the Phase 3 items).
Also unresolved: `local`'s Helmfile releases are still technically
adoptable via `make deploy ENV=local` even though Flux now owns them —
`make diff ENV=local` still renders/diffs fine against the live (now
Flux-managed) releases, so there's no drift *today*, but running an actual
`helmfile sync` against `local` would fight helm-controller for ownership.
No guard against this exists yet; avoid running deploys against `local`
outside Flux going forward. Real Phase 8 cleanup, called out early.

**Phase 5 — CSI, remaining self-management on local. Status: pre-authored,
inert.** CRD vendoring and Flux self-management landed already in Phase 3;
nothing left to do there for local specifically. `csi-driver-nfs` as a
`HelmRelease` is prod-only (local uses hostPath, not NFS), and prod isn't
bootstrapped onto Flux until Phase 7 — no cluster exists yet to reconcile
this against. Authored anyway, ready for that point: `infrastructure/csi/`
(a `HelmRepository` + `HelmRelease`, mirroring `infrastructure/crds/`'s
shape — version `4.13.2`, kept in sync with `Makefile`'s
`CSI_DRIVER_NFS_VERSION` until `make install-csi` retires in Phase 8) and
`clusters/prd/infrastructure.yaml` (wires it in, alongside the same
`infra-crds` Kustomization `local` already has). Deliberately does **not**
include `clusters/prd/flux-system/` — that's `flux bootstrap`-generated,
not hand-written (same as `clusters/local`'s), so nothing reconciles any of
this until Phase 7 runs `make flux-bootstrap ENV=prd`; its generated
Kustomization then picks up the whole `./clusters/prd` path automatically,
no further changes needed here.

**Phase 6 — retired, merged into Phase 3.** Was "rebuild the laptop cluster
onto Flux" — folded into Phase 3 once that ran directly on the laptop
instead of a separate new machine. Numbering left as-is rather than
renumbering every phase after it.

**Phase 7 — prod cutover. Status: done.** `HelmRelease.spec.releaseName`
(`${env}--platypod--<module>`, resolved to the exact existing release names
via `postBuild.substitute`) let helm-controller adopt all 8 existing
releases in place — every one landed exactly one revision past its
pre-cutover number (`persistence` 26→27→28, `core` 27→28→29, etc.),
`deployed`, no reinstall, zero PVC churn against the 18 TB of NFS media.
78/78 pods `Running`/`Completed` post-cutover; spot-checked
`grafana`/`jellyfin`/`homepage`.platypod.ovh all still routing (302 to
Authelia, as expected). `v1.0.0` tagged in both `platypod/stack` and
`platypod-sops`, lockstep — both `GitRepository`s confirmed resolved to
the tag, not `main`, via `flux get sources git`.

Sequencing note (not in the original one-liner): `flux bootstrap` always
generates `spec.ref: {branch: main}`, so the semver gate can't be a
precondition of the cutover itself — bootstrapped on `main` first (the
actual adoption moment), verified full health, **then** hand-edited
`clusters/prd/flux-system/gotk-sync.yaml`'s `spec.ref` (and
`clusters/prd/secrets.yaml`'s `platypod-sops` `GitRepository`) from
`branch: main` to `semver: ">=1.0.0"`, then tagged. Means the tag always
points at content already proven healthy, never an unverified guess.
**Maintenance note**: re-running `make flux-bootstrap ENV=prd` (e.g. for a
Flux version bump) regenerates `gotk-sync.yaml` and silently reverts
`spec.ref` back to `branch: main` — re-apply the semver edit after any
future re-bootstrap.

Three new things found doing this for real (beyond what Phase 4 already
covered) — see gotchas 12-14 below.

**Phase 8 — decommission. Status: done.** Turned out bigger than the
one-liner: retired `diff`/`deploy`/`deploy-base`/`destroy`/`require-values`/
`link-values`/`decrypt-secrets`/`install-csi` from the Makefile, deleted
`helmfile.yaml.gotmpl`, `values/default/` (see gotcha 15 — this is also what
surfaced that regression), `values/local/`/`values/prd/`, `bin/helm.sh` (a
second, fully separate Helmfile-wrapping script, never wired into the
Makefile, found auditing this), and `platypod-sops/stack/<env>/`
(the Helmfile-era secrets copy). Rewrote
[make-targets.md](make-targets.md), [operations.md](operations.md),
[conventions.md](conventions.md)'s structure/adding-a-service sections, and
fixed now-broken command references in `docs/TODO.md`,
`src/dev-tools/README.md`, `bin/README.md`, `bin/setup-local-dns.sh`,
`stack/README.md`, `stack/CLAUDE.md`, and the top-level `platypod/README.md`.
`install-deps`, `build`, `setup-*-dns`, and `proxy-*` targets survive
untouched, as planned — though `install-deps.sh`'s own helmfile/helm-diff
installation is now dead code, not yet removed (flagged as a follow-up, not
blocking). `setup-local`'s bootstrap chain changed shape (Flux now brings up
all 8 modules at once instead of a manual "base only" stage) but hasn't been
exercised end-to-end since — the one real rebuild this migration did
(Phase 3) predates the change.

**Phase 9 (deferred) — image automation.** `image-reflector` + `image-automation`
for the four GHCR images, with a semver `filterTags` policy so only `vX.Y.Z` tags
are considered and the `:latest` tag both CI workflows also push is ignored.
Images without an `ImagePolicy` and without a `$imagepolicy` marker are never
touched, so today's "every image pinned" rule holds by default and tracking is
opt-in per image. Deliberately last: it is the original motivation but the
smallest piece, and only makes sense once Git is authoritative.

## Gotchas requiring empirical verification

1. **Flux forbids remote Kustomize bases. Verified in Phase 3.** `make
   install-crds` applies Traefik CRDs from `raw.githubusercontent.com`;
   kustomize-controller runs with network access disabled, so the CRDs had to
   be **vendored** into `infrastructure/crds/` — done, reconciling cleanly via
   the `infra-crds` Kustomization. Side benefit: explicitly pinned now.
2. **ConfigMap/Secret hash suffixes break `valuesFrom`. Verified + refined in
   Phase 4.** `configMapGenerator` (substrate/registry/per-module tiers, all
   built by the *same* `apps/base/` Kustomization as the `HelmRelease`s that
   reference them) needs `kustomizeconfig.yaml` teaching Kustomize's
   nameReference transformer about `HelmRelease.spec.valuesFrom[].name` —
   confirmed via `kubectl kustomize`: the hashed name gets substituted in
   correctly. But `secretGenerator` (the Secrets tier) is built by a
   **separate** Kustomization, sourced from the `platypod-sops`
   `GitRepository` — nameReference only rewrites references *within one
   kustomize build's own resource graph*, so it can never reach across to a
   different Kustomization's output. A hashed name there would leave every
   `HelmRelease` pointing at a Secret name that doesn't exist. Fixed:
   `disableNameSuffixHash: true` on that one `secretGenerator` — a stable,
   predictable name instead, referenced directly. Trade-off: no
   automatic-rollout-on-content-change from the name alone, acceptable since
   helm-controller re-renders values every reconcile interval regardless.
3. **Drift correction vs. the setup Jobs — the main operational risk.** The
   post-install/post-upgrade hook Jobs re-run on every Helm upgrade, and
   `torrent-clients-setup` carries the 15-min-per-*arr wait loop. Frequent
   Flux-triggered upgrades would re-run them repeatedly. Start with drift
   correction **disabled**; enable deliberately, later.
4. **In-place release adoption. Verified in Phase 4 (`persistence`).**
   helm-controller *does* adopt an existing Helmfile-created release by
   `releaseName` + namespace rather than reinstalling — no ownership
   labels/annotations needed patching first; it just worked. Confirmed via
   `helm list`: the release went from revision 1 (Helmfile) straight to
   revision 3 (helm-controller), no reinstall, no PVC churn.
5. **PodSecurity.** `prd-platypod` stays `baseline`; confirm `flux-system` is
   satisfied (Flux ships restricted-compatible manifests).
6. **No `make destroy MODULE=` equivalent.** Deletion becomes "remove from Git +
   `prune: true`". `flux suspend` stops reconciliation but does not uninstall.
7. **Flux's default Helm `--wait` breaks `WaitForFirstConsumer` PVCs. Found
   in Phase 4 (`persistence`).** Not in the original gotcha list — discovered
   live. `persistence`'s PVCs use `WaitForFirstConsumer` binding and are
   provisioned *ahead* of the pods that will actually consume them
   (media/games modules, ported later) — sitting `Pending` until then is
   correct, expected behavior. Helmfile's `sync` never passed `--wait`, so
   this was invisible before. Flux's `HelmRelease` enables Helm's `--wait`
   by default, which blocked the whole release on a PVC bind that was never
   going to happen yet — failed after the 5-minute timeout with "exceeded
   maximum retries: cannot remediate failed release" before the fix. Fixed:
   `spec.install.disableWait` / `spec.upgrade.disableWait: true` on
   `persistence`'s `HelmRelease`, matching Helmfile's actual prior behavior.
   Any other module whose PVCs are provisioned ahead of their consumers
   needs the same treatment — check for this specifically when porting
   `media`/`games`.
8. **`HelmChart`'s default `reconcileStrategy: ChartVersion` silently
   serves a stale chart. Found in Phase 4 (`observability`).** None of
   these charts bump `Chart.yaml`'s `version` (all static `0.1.0`), so the
   default strategy — repackage only when that field changes — meant
   source-controller kept serving a chart built *before* a template-only
   git fix, even after the `GitRepository` itself had the fix. The
   `HelmRelease` kept failing with the pre-fix error indefinitely, no
   matter how many times `flux reconcile source git` was re-run. Fixed:
   `reconcileStrategy: Revision` on all 8 `HelmRelease`s' `chart.spec` —
   repackages on every git revision change instead, matching how Helmfile
   always worked (git-driven, no chart-version bumping).
9. **Revision strategy's `+<gitsha>` build metadata breaks any label that
   embeds `.Chart.Version` raw. Found in Phase 4, immediately after fixing
   gotcha 8.** `reconcileStrategy: Revision` appends `+<shortsha>` to
   `.Chart.Version` (valid SemVer build metadata). 16 templates across
   `core`/`security`/`observability`/`media` stamp
   `chartVersion: {{ .Chart.Version }}` as a literal label — one of them
   (`core/templates/traefik/traefik--deployment.yaml`'s
   `kubernetesingress.labelselector`) uses it as a **live Traefik watch
   selector**, not just decoration. `+` isn't a valid Kubernetes label
   character, so every resource carrying that label failed server-side
   apply the moment `reconcileStrategy: Revision` landed — a real
   regression introduced by fixing gotcha 8, not a pre-existing bug. Fixed:
   `{{ .Chart.Version | replace "+" "_" }}` everywhere it's set (all 16
   sites, selector included) — a no-op under Helmfile's plain render
   (no `+` ever appears there), confirmed byte-identical via
   `make diff ENV=prd`.
   - **Corrects an earlier wrong claim** (from investigating the
     `prometheus-snmp-exporters/ingress-route.yaml` duplicate-`IngressRoute`
     bug, fixed same session): checking prod's live cluster directly showed
     the exact same duplicate has been rendering there too, on a `deployed`,
     healthy release, for months — the "never caught because observability
     was never installed on prod" explanation was false. The real reason it
     only surfaced on `local`: Helm's duplicate-resource-ID guard ("may not
     add resource with an already registered id") only fires on a fresh
     `install`, not on `upgrade` against an already-existing release — prod
     has only ever gone through `upgrade` since this bug was introduced.
     Deleting the stray file is still correct regardless of the mechanism.
10. **Local's node can't fit everything the charts ask for — two separate
    walls, both capacity, not config bugs. Found in Phase 4
    (`observability`).** (a) `loki` and `otel-collector-gateway` Deployments
    had no per-component `enable` gate at all — the whole `observability`
    module was all-or-nothing — and both sat `FailedScheduling: Insufficient
    memory` on `local`'s single schedulable node. Added `enable` flags
    (defaulting `true`, so prod/any fully-resourced env is unaffected) and
    disabled both in `platypod-sops`'s `local` secrets. (b)
    `opentelemetry-collector-collector`'s DaemonSet wants a second replica
    on the control-plane node (to collect its metrics too); that node also
    can't fit it, and Helm's default `--wait` blocks the whole release on
    DaemonSet readiness. Unlike (a), no `enable` gate makes sense here
    (prod legitimately wants both nodes covered) — used
    `install.disableWait`/`upgrade.disableWait: true` on `observability`'s
    `HelmRelease` instead, same precedent as gotcha 7's `persistence` fix,
    justified because this `HelmRelease` doesn't exist for prod yet (still
    Helmfile there until Phase 7) so it can't mask a real prod failure.
11. **Setup Jobs that don't check their peers' `enable` flags hang for the
    full wait-loop, not fail fast. Found in Phase 4 (`files`).**
    `torrent-clients--setup-job.yaml` and `sabnzbd--setup-job.yaml` both
    built their `ARR_APPS_JSON` (Sonarr/Radarr/Readarr) unconditionally,
    and `sabnzbd--setup-job.yaml`'s Prowlarr/indexer section ran regardless
    of `prowlarr.enable`. Harmless on prod (everything's enabled), but with
    `local` deliberately running only a subset per service (undersized
    node), each Job's `wait_for()` polled a Service that was never deployed
    — DNS never resolves for a Service that doesn't exist — for the full
    90×10s=15min *per disabled app*, up to 45 min combined, on every
    install/upgrade. Fixed: gate each app's inclusion in `ARR_APPS_JSON` on
    its own `.enable` (mirrors the existing `TORRENT_CLIENTS_JSON` pattern
    already used for Transmission/QBittorrent), and skip the whole Prowlarr
    section outright when `prowlarr.enable` is false. No functional change
    on prod — confirmed via `make diff ENV=prd` (JSON key-order only, an
    artifact of `toJson`'s alphabetical field ordering vs. the old
    hand-written literal).
12. **`Kustomization.spec.postBuild.substitute` scans the WHOLE rendered
    manifest, not just the fields meant to vary. Found in Phase 7,
    live on prod.** Making `apps/base/` shared across clusters (Phase 7)
    needed `${env}` tokens in the 8 `HelmRelease`s, resolved per cluster via
    `postBuild.substitute`. That substitution runs in strict mode over
    *every* `${...}`-looking sequence in the fully-rendered output —
    including comments embedded in generated `ConfigMap` data, which have
    nothing to do with the substitution. A doc comment in
    `values/default/dev-tools.yaml` describing Wiki.js's own OIDC callback
    URL pattern (`${host}/login/${key}/callback`) broke the `apps`
    Kustomization outright on *both* `local` and `prd` the moment either
    reconciled against the new commit — `envsubst error: variable
    substitution failed: variable not set (strict mode): "host"`. Fixed
    with Flux's `$$` escape (`$${host}`, a literal `$` the scanner skips) —
    invisible to Helm, which strips comments before rendering. Any future
    prose anywhere in the 9 default value files that happens to contain
    `${...}` will trip this the same way on every cluster at once — worth a
    quick `grep -rn '\${' values/default/'` before merging new comments
    near curly braces.
13. **`flux create secret git --export` writes `stringData` (plain text),
    not `data` (base64) — and `gh repo deploy-key add` has no `--read-only`
    flag. Found in Phase 7, scripting `flux-sops-secrets`.** The first
    version of the target read `.data."identity.pub" | base64 -d`, which
    resolved to `null` → empty string, silently producing a garbage
    3-byte "public key" that `gh repo deploy-key add` then rejected in a
    way that wasn't obviously about the wrong field (an "unknown flag"
    error from the *next* problem masked the first one in the same run).
    Fixed: read `.stringData."identity.pub"` directly, no base64 decode;
    drop `--read-only` entirely (it's the default — only `-w`/`--allow-write`
    opts into write access, there's no flag to explicitly request the
    default). Caught because this ran for real against prod, not `local` —
    `local`'s original setup used the same broken assumption but never
    surfaced it because it was done by hand, one field at a time, not
    scripted until this phase.
14. **A `HelmRelease` with no explicit `spec.releaseName` doesn't stay
    inert next to an existing imperative release of the same chart — it
    silently takes ownership. Found in Phase 7, post-cutover audit
    ("are we sure this actually worked?"), on prod's `csi-driver-nfs`.**
    Every one of the 8 app modules got `releaseName` set explicitly for
    in-place adoption (gotcha 4) — but Phase 5's `infrastructure/csi/helm-release.yaml`
    was authored and left inert for months without that same care, since
    at the time nothing reconciled it yet. When Phase 7's bootstrap
    finally applied it, Flux used its own default release name
    (`kube-system-csi-driver-nfs`, `<namespace>-<name>`) instead of the
    original imperative install's name (`csi-driver-nfs`, from
    `make install-csi`, predating this migration). Helm's `install` did
    **not** refuse — it silently rewrote the live `csi-nfs-controller`
    Deployment's and `csi-nfs-node` DaemonSet's `meta.helm.sh/release-name`
    annotation to the new release, leaving the old `csi-driver-nfs` release
    record as an orphaned ghost (still `helm list`-visible as `deployed`,
    owning nothing). No live disruption — the underlying pods were never
    touched, same age throughout — but a real latent risk: `helm uninstall
    csi-driver-nfs` reads *its own* stored manifest to decide what to
    delete, not current ownership annotations, so running that later would
    have deleted the live (now differently-owned) CSI driver objects by
    name. Fixed: deleted only the orphaned release's Helm storage Secret
    (`sh.helm.release.v1.csi-driver-nfs.v1` in `kube-system`) — pure
    bookkeeping, verified zero live resources still referenced it before
    deleting, confirmed the running pods' age/restart-count were unchanged
    after. **Any future `HelmRelease` authored for something that might
    already exist outside Flux needs an explicit `releaseName` matching the
    existing release from the start — not just the 8 already-known
    modules** — and this one slipped through because it was "pre-authored,
    inert" for a whole phase before ever actually reconciling, so the usual
    right-after-authoring verification never caught it.
15. **`values/default/` and `apps/base/values/` silently drifted — a real,
    active prod regression, caught auditing Phase 8, not during Phase 4 or
    7.** Phase 4 copied `values/default/*.yaml` into `apps/base/values/`
    once, for Flux to consume — but nothing kept the two in sync
    afterward. A later fix this session (adding `enable: true` gates for
    `loki`/`otelCollector.gateway`, so `local` could disable just those
    two for its capacity constraints) only ever edited `values/default/`
    — the copy that had stopped mattering the moment Flux took over
    rendering. `apps/base/values/observability.yaml` and `registry.yaml`
    kept the old, pre-gate content, where those two fields simply didn't
    exist — which Helm's `{{- if .Values.X.enable }}` reads as falsy, same
    as an explicit `false`. Both Deployments silently stopped rendering
    **everywhere**, including prod, from the moment Phase 7's cutover
    picked up that commit — no pod crash, no `Ready: False`, just two
    Deployments that quietly ceased to exist. Prod lost centralized
    logging (Loki) and its otel ingestion gateway (feeding
    mimir/tempo/pyroscope) for roughly the same window this session
    thought Phase 7 was fully verified — caught only because Phase 8
    diffed the two directories before deleting one of them. Fixed:
    resynced the copies, tagged `v1.0.1`, confirmed both pods `Running`
    within minutes. Phase 8 deletes `values/default/` entirely (see
    below) specifically to make this class of drift structurally
    impossible going forward — `apps/base/values/` becomes the one and
    only source. **The lesson generalizes beyond this one incident**: a
    pod-health check (`kubectl get pods`, `flux get helmreleases`) cannot
    catch "a whole Deployment silently stopped being desired state" — only
    diffing against a known-good baseline (chart-level `helm get manifest`
    comparison, or golden-manifest diffing as used in Phase 2) would have.

## Open items

- **Environment naming — done (Phase 3).** The laptop is now `local`;
  `dev` is free for the eventual WAN-reachable machine (still blocked on
  hardware — a 2017 Mac mini can't run Talos). Renamed across
  `infra/environments/*.tfvars`, `.generated/<env>/`,
  `stack/values/dev/`→`values/local/`, `platypod-sops/stack/dev/`→`local/`,
  and every `ENV=dev`/`dev-platypod` reference in both repos' Makefiles,
  scripts, and docs — sequenced with the Phase 3 rebuild, per the precedent
  in `infra/TODO.md` (an env name is baked into live Terraform state as
  attribute values, not just resource addresses; destroy-under-old-name +
  apply-fresh-under-new-name is the only clean path).
- **`stack/docs/TODO.md` is stale on secrets** — it states all secrets are
  plaintext in Git including `values/prd/values.yaml`. That file has never been
  committed. The real (narrower) exposure is Phase 0 above. Fix separately.
- **`infra/docs/architecture.md` ingress section is stale** — it documents
  `WAN:443 → router → host:9443 → nginx → Traefik (MetalLB IP)`, but prod has no
  MetalLB post-cutover and Traefik is reached on chuwi's Service `externalIP`.
  The nginx stream proxy still serves the game-server ports. Fix separately.
- **Dev machine sizing** — 16 GB. The laptop's 4 GB worker could not run all
  modules at once; confirm dev can, or carry per-cluster enable flags.
