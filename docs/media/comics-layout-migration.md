# Comics layout: `bds` and `mangas` as top-level folders (runbook)

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
