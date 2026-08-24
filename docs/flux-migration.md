# Flux migration (plan)

> **Status: Phases 0-2 done (dev-only where secrets are involved); Phase 3
> onward not started.** It records the decisions (with rejected alternatives)
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

**Phase 3 — Flux on the new dev machine (greenfield).** `flux bootstrap` against
`main`, path `clusters/dev`. Nothing at risk; this is where the gotchas below get
discovered.

**Phase 4 — port the 8 modules to `HelmRelease` on dev.** Verify `dependsOn`
reproduces the module ordering, especially `files` after `media`.

**Phase 5 — CRDs, CSI, self-management on dev.** Vendor Traefik CRDs; csi-driver-nfs
as a `HelmRelease`; Flux managing its own manifests. `infra/` gains a bootstrap step.

**Phase 6 — local cluster.** Rebuild the laptop cluster onto Flux, validating the
mkcert/self-signed path and confirming the tier split holds for a cluster with no
ACME and most modules disabled.

**Phase 7 — prod cutover.** Set `HelmRelease.spec.releaseName` to the **exact
existing release names** (`prd--platypod--core`, …) so helm-controller adopts the
existing releases in place rather than reinstalling — a reinstall would churn PVs
against 18 TB of NFS media. Must be proven on dev in Phase 4 first. Tag `v1.0.0`
**in both `platypod/stack` and `platypod-sops`** to arm prod's semver ref on
each — lockstep tagging, see the SOPS decision above.

**Phase 8 — decommission.** Retire the Helmfile targets and the NFS values
symlink + `REQUIRE_VALUES` guard; rewrite [make-targets.md](make-targets.md) and
[operations.md](operations.md). `install-deps`, `build`, `setup-*-dns`, and
`proxy-*` survive untouched — none of them wrap Helmfile.

**Phase 9 (deferred) — image automation.** `image-reflector` + `image-automation`
for the four GHCR images, with a semver `filterTags` policy so only `vX.Y.Z` tags
are considered and the `:latest` tag both CI workflows also push is ignored.
Images without an `ImagePolicy` and without a `$imagepolicy` marker are never
touched, so today's "every image pinned" rule holds by default and tracking is
opt-in per image. Deliberately last: it is the original motivation but the
smallest piece, and only makes sense once Git is authoritative.

## Gotchas requiring empirical verification

1. **Flux forbids remote Kustomize bases.** `make install-crds` currently applies
   Traefik CRDs from `raw.githubusercontent.com`; kustomize-controller runs with
   network access disabled, so the CRDs must be **vendored** into the repo. Side
   benefit: they become explicitly pinned.
2. **ConfigMap/Secret hash suffixes break `valuesFrom`.** Both
   `configMapGenerator` (globals/services/per-module tiers) and
   `secretGenerator` (the Secrets tier, wrapping decrypted content from
   `platypod-sops`) append a content hash, and Kustomize's nameReference
   transformer does not know about `HelmRelease.spec.valuesFrom[].name` for
   either kind. Without a `kustomizeconfig.yaml` teaching it both paths,
   releases silently reference nonexistent ConfigMaps/Secrets. Verify on dev
   before trusting it.
3. **Drift correction vs. the setup Jobs — the main operational risk.** The
   post-install/post-upgrade hook Jobs re-run on every Helm upgrade, and
   `torrent-clients-setup` carries the 15-min-per-*arr wait loop. Frequent
   Flux-triggered upgrades would re-run them repeatedly. Start with drift
   correction **disabled**; enable deliberately, later.
4. **In-place release adoption** (Phase 7) — confirm helm-controller adopts an
   existing release by `releaseName` + namespace rather than reinstalling, and
   check whether ownership labels/annotations need patching first.
5. **PodSecurity.** `prd-platypod` stays `baseline`; confirm `flux-system` is
   satisfied (Flux ships restricted-compatible manifests).
6. **No `make destroy MODULE=` equivalent.** Deletion becomes "remove from Git +
   `prune: true`". `flux suspend` stops reconciliation but does not uninstall.

## Open items

- **Environment naming.** Today `ENV=dev` is the laptop. After this migration the
  laptop is `local` and the new machine is `dev`. Renaming touches
  `infra/environments/*.tfvars`, `.generated/<env>/`, and the host LaunchDaemons
  (`com.platypod.nat.<env>`, `~/.platypod/<env>`). Per the precedent in
  [../../infra/docs/decisions.md](../../infra/docs/decisions.md), an env name is
  baked into a live cluster and should not be renamed in place — but the laptop
  cluster is ephemeral, so the rename is cheap **at its next rebuild**. Sequence
  the rename with that rebuild rather than as a standalone change.
- **`stack/docs/TODO.md` is stale on secrets** — it states all secrets are
  plaintext in Git including `values/prd/values.yaml`. That file has never been
  committed. The real (narrower) exposure is Phase 0 above. Fix separately.
- **`infra/docs/architecture.md` ingress section is stale** — it documents
  `WAN:443 → router → host:9443 → nginx → Traefik (MetalLB IP)`, but prod has no
  MetalLB post-cutover and Traefik is reached on chuwi's Service `externalIP`.
  The nginx stream proxy still serves the game-server ports. Fix separately.
- **Dev machine sizing** — 16 GB. The laptop's 4 GB worker could not run all
  modules at once; confirm dev can, or carry per-cluster enable flags.
