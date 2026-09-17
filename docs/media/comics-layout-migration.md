# Comics layout: `bds` and `mangas` as top-level folders (runbook)

> **Executed on prod 2026-09-17.** Result: `bds` 62 series / 116 GB, `mangas`
> 7 series / 5.1 GB / 487 CBZ, Suwayomi 477 chapters still marked downloaded and
> verified serving a page from one. Nothing was deleted. See
> [What actually happened](#what-actually-happened) for the two gotchas the
> steps below did not predict — read that section before re-running this on local.

One-time migration, 2026-09-17:

```
 media/manga/bd      ->  media/bds      (116 GB, 62 series)
 media/manga/mangas  ->  media/mangas   (5.1 GB)
 media/manga/thumbnails  ->  app volume (Suwayomi scratch, ~1 MB, 17 files)
 media/manga/        ->  gone
```

BD and manga end up as siblings under the media root, next to
`books`/`anime`/`movies`/`series`, and both become manageable from the laptop.

## What was actually wrong

`media/manga/` was never a category — it was Suwayomi's download root. Suwayomi
hard-codes its layout as `<downloadsPath>/mangas/<source>/<series>/<chapter>`
and drops a `thumbnails/` next to it, so `manga/mangas` and `manga/thumbnails`
were Suwayomi's own directories, and `manga/bd` was 116 GB of BD parked inside
another service's working directory.

Two things then made it unmanageable from the laptop:

1. Suwayomi's init container ran `chown -R 1000:1000` over its whole download
   root on **every pod start** — so it repeatedly took ownership of all of BD.
2. Suwayomi's process umask is `0022`, so every directory it created came out
   `0755`.

Over NFS the laptop presents uid 502 / gid 20, which matches neither owner
(1000) nor group (1000) — so it fell through to the `other` bits and had no
write access. Every *other* folder on the share happens to be mode `2777`, which
is the only reason the rest of the tree works.

Fixed by mode and layout, not by identity:

- Suwayomi no longer gets a download root on the share at all. Only the `mangas`
  library folder is mounted into it, at `<downloadsPath>/mangas`; the download
  root itself now lives on the app volume, so `thumbnails/` (and anything else
  Suwayomi invents) never touches the media share.
- The recursive `chown` is gone. The init container only asserts the
  mountpoint's own mode, non-recursively: `2777` + setgid to
  `media.system.groupId`.
- Suwayomi is re-exec'd under `umask 002`, so new content is group-writable and
  inherits gid 20 from the setgid bit — which is the laptop's gid.

Suwayomi keeps running as its native uid 1000. It could run as another uid (the
JAR is 0777, contrary to an older comment claiming 0750), but its JCEF/Chromium
cache dirs under `/home/suwayomi` are `0700` owned by 1000, and the JS-heavy
sources need that browser. Changing mode is enough and risks nothing.

## Data safety

Everything here is a rename within one NFS volume plus a copy of 17 thumbnails.
**No file is deleted at any point**, and nothing depends on metadata surviving.

- **Suwayomi** resolves chapter files from `<downloadsPath>/mangas/...` at read
  time rather than storing absolute paths, and the tree *below* `mangas/` is
  unchanged — so every existing download stays recognized with no DB edit.
- **Komga** does store absolute per-book paths, so its two old libraries are
  replaced rather than moved. The new roots also carry new names (`bd` -> `bds`,
  `manga` -> `mangas`), which means the create-if-missing komga-setup Job builds
  them automatically and the old ones are deleted by hand afterwards. Deleting a
  Komga library removes database rows only — upstream is explicit that "your
  media files will not be affected".
- Read progress and Komga metadata for these two libraries are **not** carried
  over; they are re-derived by the rescan. That is a deliberate, accepted
  trade-off here — it is what lets the migration be a pure file move instead of
  database surgery.

## Steps

```bash
export TALOSCONFIG=../infra/.generated/prod/talosconfig
export NODE=$(kubectl -n prd-platypod get pod -l app=suwayomi -o jsonpath='{.items[0].spec.nodeName}')
```

### 1. Stop the two writers

```bash
kubectl -n prd-platypod scale deploy/suwayomi deploy/komga --replicas=0
kubectl -n prd-platypod wait --for=delete pod -l app=suwayomi --timeout=120s
kubectl -n prd-platypod wait --for=delete pod -l app=komga --timeout=120s
```

### 2. Rescue Suwayomi's thumbnails

They are about to stop being on the share. 1.1 MB, so just copy them aside;
they are regenerable, this is only to avoid a visible re-fetch.

```bash
cp -a /volume1/kubernetes/media/manga/thumbnails /tmp/suwayomi-thumbnails
```

### 3. Move the two libraries (on the NAS, or as root)

Same volume, so both are `rename(2)` — instant, no copying of the 116 GB. Run
this on the Synology: renaming inside `manga/` needs write on `manga/`, which is
exactly the permission the laptop lacks.

```bash
cd /volume1/kubernetes/media
mv manga/bd     bds
mv manga/mangas mangas
```

### 4. Normalise the modes

One-time repair of what the old umask left behind. `a+rwX` (capital X) sets the
execute bit on directories only, never on comic files.

```bash
chmod -R a+rwX bds mangas
chmod 2777 bds mangas        # setgid, matching the other top-level folders
chgrp -R 20 bds mangas       # gid 20 = media.system.groupId = the laptop's gid
```

### 5. Retire the old folder

It should now hold only Synology/macOS droppings. Check before removing, and
note `@eaDir` is the NAS's own index dir.

```bash
ls -la manga/                 # expect: thumbnails, @eaDir, .DS_Store — nothing else
rm -rf manga/
```

If anything else is in there, stop and look at it first.

### 6. Deploy

Merge the chart change so Suwayomi picks up the new mounts, the umask wrapper
and the dropped chown, and so komga-setup learns the two new libraries.

### 7. Restore the thumbnails onto the app volume

```bash
talosctl -n "$NODE" cp /tmp/suwayomi-thumbnails \
  /var/local/platypod/volumes/config/suwayomi/downloads/thumbnails
```

### 8. Bring the services back

```bash
kubectl -n prd-platypod scale deploy/suwayomi deploy/komga --replicas=1
```

komga-setup runs as a post-upgrade hook and creates `bds` -> `/data/bds` and
`mangas` -> `/data/mangas`. Then, in the Komga UI, **delete the two stale
libraries** `bd` and `manga` — their roots no longer exist. Files are untouched
by this.

### 9. Verify

- Komga: `bds` scans to 62 series, `mangas` to its existing series.
- Suwayomi: previously downloaded chapters still show as downloaded and open.
- Suwayomi: download one new chapter, then from the laptop confirm you can
  create a folder inside the new series directory and rename a file. This is the
  actual acceptance test — it proves the umask wrapper works, not just the
  one-time `chmod`.

```bash
mkdir /Users/pittinic/nfs/kubernetes/media/mangas/.wtest && \
  rmdir /Users/pittinic/nfs/kubernetes/media/mangas/.wtest && echo OK
```

## Rollback

Nothing is destroyed, so rollback is the moves in reverse:

```bash
cd /volume1/kubernetes/media
mkdir -p manga
mv bds    manga/bd
mv mangas manga/mangas
cp -a /tmp/suwayomi-thumbnails manga/thumbnails
git revert <the chart commit>     # then let Flux reconcile
```

Then delete the `bds`/`mangas` libraries in Komga and let the reverted
komga-setup recreate `bd` and `manga`.


## What actually happened

Two things the plan above did not predict.

### Helm leaves the old volumeMount behind

`volumeMounts` merges on `mountPath` as the key, so the upgrade produced the
**union** of old and new — the pod came up with three mounts, including the
stale `downloads` -> subPath `manga`:

```
/home/suwayomi/.local/share/Tachidesk              subPath=suwayomi
/home/suwayomi/.local/share/Tachidesk/downloads    subPath=manga     <- stale
/home/suwayomi/.local/share/Tachidesk/downloads/mangas  subPath=mangas
```

The rendered chart was correct (two mounts); only the live object was wrong.
It "worked" — `mangas` was mounted over the top — but `downloads/` was still the
NFS `manga/` folder, which is precisely what this change exists to stop.

Fix: delete the Deployment and let Helm recreate it, rather than trusting the
upgrade to converge.

```bash
kubectl -n prd-platypod delete deploy suwayomi
flux -n prd-platypod reconcile helmrelease media --force
```

Always confirm the live spec afterwards, not just the render:

```bash
kubectl -n prd-platypod get deploy suwayomi \
  -o jsonpath='{range .spec.template.spec.containers[0].volumeMounts[*]}{.mountPath}{" subPath="}{.subPath}{"\n"}{end}'
```

That stale mount also left an empty root-owned `media/manga/mangas` behind,
created by kubelet as a mountpoint for the nested subPath. Harmless, removed.

### The group on the library folder drifts to 100

`media/mangas` was set to gid 20 during the move, and was found back at gid 100
(`users`, the NAS-native group) after the first pod start — then stayed at 20
once re-set. `chgrp` works and `chmod` does not reset it, so something NAS-side
did it; the cause was not pinned down.

It does not matter in practice: the folder is `2777`, and the laptop is in both
gid 20 (primary) and gid 100 (supplementary, `_lpoperator`), so it can write
either way. Worth knowing before treating a gid-100 sighting as a regression.

## Verifying the permission chain

The one test that matters is not the one-time `chmod` — it is whether content
Suwayomi creates *later* is still writable. Confirmed end to end:

```
process umask (the JCEF/Java procs, not tini at PID 1) : 0002
new dir  created by Suwayomi : uid=1000 gid=20 mode=2775
new file created by Suwayomi : uid=1000 gid=20 mode=664
laptop (uid 502, gid 20)     : mkdir / rename / create / delete all OK
```

```bash
# process umask -- check the java/jcef procs, NOT /proc/1 (that is tini, 0022)
kubectl -n prd-platypod exec deploy/suwayomi -c suwayomi -- sh -c \
  'for p in /proc/[0-9]*; do case "$(tr "\0" " " < $p/cmdline)" in *jcef*|*java*) grep -i ^Umask $p/status;; esac; done'

# laptop write test
mkdir /Users/pittinic/nfs/kubernetes/media/mangas/.wtest && \
  rmdir /Users/pittinic/nfs/kubernetes/media/mangas/.wtest && echo OK
```

## Doing the file moves without NAS shell access

Step 3 says "on the Synology". A root pod with an **inline NFS volume** does the
same job from the cluster, and avoids contending for the RWO `media` PVC:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: media-layout-migration, namespace: prd-platypod}
spec:
  restartPolicy: Never
  containers:
  - name: shell
    image: busybox:1.37.0
    securityContext: {runAsUser: 0}
    command: ['sh','-c','sleep 1800']
    volumeMounts: [{name: media, mountPath: /data}]
  volumes:
  - name: media
    nfs: {server: 192.168.1.30, path: /volume1/kubernetes/media}
```

PodSecurity `baseline` warns about `restricted` here but admits the pod. Root is
not squashed on this export, so `mv`/`chgrp`/`chmod` all work.

## Left behind

`media/manga/` still exists, holding only the now-duplicated `thumbnails/`
(also restored onto the app volume), plus the NAS's `@eaDir` and a `.DS_Store`.
It is inert. Remove it once the new layout has proven itself.
