# Branching: `dev` deploys local, `main` deploys prod

The one rule:

> **`dev` is what local runs. `main` is what prod runs. Merging `dev` into
> `main` IS the prod deployment.** There is no other promotion step, and no
> tag is involved.

Adopted 2026-09-01, replacing "every push to `main` reaches prod in ~1 minute".

## What tracks what

| Object | local cluster | prod cluster |
|---|---|---|
| `flux-system` GitRepository (stack) | `branch: dev` | `branch: main` |
| `platypod-sops` GitRepository | `branch: dev` | `branch: main` |
| `stack-image-automation` GitRepository | `branch: dev` | `branch: dev` |
| `ImageUpdateAutomation` checkout + push | `dev` | **`dev`** |
| Kustomization path | `./clusters/local`, `./apps/local-overlay` | `./clusters/prd`, base values |

Both repos use the identical split — that symmetry is deliberate. `platypod-sops`
used to be pinned to `semver: ">=1.0.0"` while `stack` tracked a branch, and that
mismatch was a standing source of confusion.

A semver ref resolves to the **highest** matching tag, not the pinned floor. When
prod's sops ref was moved to `main` it was verified a no-op on exactly that basis
(`>=1.0.0` was sitting on `v1.0.1`, identical to `main`). Check it the same way if
it ever moves again: `git diff v<highest>..main -- clusters/prd/`.

## Day to day

```sh
# ship something
git switch dev && git commit && git push origin dev     # -> local, ~1 min

# promote to prod once you're happy with it
git switch main && git merge --ff-only dev && git push origin main
```

The merge is a fast-forward. See "Why `main` cannot drift" below for why that
is guaranteed rather than merely usual.

Rollback is an ordinary git operation on `main` — revert the merge, or reset
`main` to the previous commit and force-push. Unlike the retired tag gate,
there is no "you can't go back to an old tag because semver always resolves
the highest" trap.

## Image automation writes to `dev`, never `main`

All three `ImageUpdateAutomation` objects — local's two and **prod's own** —
check out and push to `dev`.

Prod's is the counter-intuitive one, and it is the load-bearing part of the
whole design. `ImageUpdateAutomation` can only ever push to a *branch*; it
cannot create a tag. If prod's automation pushed to `main`, every new image
release would land directly on prod's deploy branch and auto-deploy, and the
promotion gate would apply to hand-written config changes only — which is
precisely the thing it exists to prevent. Pointed at `dev`, a new image is
*staged* for promotion instead: local picks it up, and it reaches prod when
you merge.

Local keeps its `-local` ImagePolicy set (ranges ending `-0`, so prereleases
match) writing `apps/local-overlay/`, while the plain final-release policies
write `apps/base/values/`. Both land on `dev`. Prod's automation also writes
`apps/base/values/` on `dev`; the two compute the same final-release value and
converge on an identical write, so they do not fight.

## Why `main` cannot drift

Nothing commits to `main` except a `dev` merge. Automation writes only to
`dev`. So `main` is always an ancestor of `dev`, every promotion is a
fast-forward, and there is no back-merge chore and no sync robot to maintain.
This is by construction, not by discipline.

Two things can still put a commit on `main` directly, both rare and
deliberate:

- `flux bootstrap ENV=prd`, which commits regenerated `flux-system` manifests
- a hand-written emergency hotfix

After either, merge `main` back into `dev` once so the branches re-converge.
If that is ever missed, the next promotion stops being a fast-forward and
`--ff-only` fails loudly rather than drifting silently — which is the intent.

## The `flux bootstrap` footgun

`flux bootstrap` regenerates `clusters/<env>/flux-system/gotk-sync.yaml` with
whatever branch it was invoked for, **and strips any comments in it**. After
re-bootstrapping local, `spec.ref` must be set back to `branch: dev` by hand.

This is not hypothetical. The previous ref decision (retiring prod's semver
gate in `91cf21d`) was explained in a comment block that the very next
bootstrap run erased seven minutes later. The decision survived; the reason did
not, and months later the bare `branch: main` was misread as configuration
drift and nearly "fixed" — which would have severed prod's image automation and
rolled prod back dozens of commits.

Hence this file. It is the authoritative record precisely because Flux never
rewrites it. Trust it over any comment inside a `gotk-sync.yaml`.

## Transition ordering (if this is ever redone)

`dev` must exist on both repos *before* any cluster is pointed at it, or the
source stops resolving. The safe sequence is: create `dev` at `main` on
`platypod-sops`; then on `stack`, commit the ref changes to `main`, create
`dev` at that same commit, and push both refs atomically
(`git push --atomic origin main dev`) so no cluster ever observes a state where
its branch is missing or the two disagree.
