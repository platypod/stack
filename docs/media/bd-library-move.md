# Moving the `bd` library out of `manga/` (runbook)

One-time migration: `media/manga/bd` → `media/bd`, making BD a top-level media
folder alongside `books`/`anime`/`movies`/`series` instead of a tenant inside
Suwayomi's download root.

**Why**, in one line: `manga/` is Suwayomi's download root, and Suwayomi's init
container runs `chown -R 1000:1000` over all of it on every pod start — so it
took ownership of 116 GB of BD and left it `1000:1000 0775`, which over NFS maps
to neither the laptop's uid nor its gid, hence "I can't create folders there".
Full rationale in the `komga.libraries` comment in
[`media.yaml`](../../apps/base/values/media.yaml).

## Read this first: the values change alone does nothing

`komga.libraries[bd].root` is already `/data/bd` in Git. That is **safe to
deploy on its own** and is *not* the migration: the komga-setup Job is
create-if-missing **by name**, so it sees a library called `bd`, skips it, and
never touches the root. A live Komga keeps pointing at the old path until you
run the steps below by hand.

## Why a plain root change would destroy the library

Komga stores an **absolute per-book path**, not a path relative to the root
(`BOOK.URL` = `file:/data/manga/bd/Cixi%20de%20Troy/...`). A library scan deletes
every book whose recorded path is not on disk, and this library has
`emptyTrashAfterScan: true`, so the deletion is immediate rather than parked in
the trash bin. Komga's own docs are explicit that a root change to a
non-overlapping path loses "all your series, books and read progress"; only
widening to a **parent** of the current path is safe, and `/data/bd` is a
sibling of `/data/manga/bd`, not a parent.

There is no API to rewrite book paths (`LibraryUpdateDto` exposes `root`, but
patching it just re-points the scan). So the migration rewrites the three
columns that carry the prefix, offline, with a backup.

Measured on prod, 2026-09-17:

| Table.column | rows with the old prefix |
|---|---|
| `LIBRARY.ROOT` | 1 (`file:/data/manga/bd/`) |
| `SERIES.URL` | 62 |
| `BOOK.URL` | 954 |
| `THUMBNAIL_BOOK.URL`, `THUMBNAIL_SERIES.URL`, `SIDECAR.*` | 0 |

`READ_PROGRESS` (39 rows) and `READ_PROGRESS_SERIES` (22) key off `BOOK_ID` /
`SERIES_ID`, **not** the path — rewriting URLs in place keeps every book's row
identity, so progress, metadata, collections and read lists all survive
untouched. `FILE_SIZE`/`FILE_LAST_MODIFIED`/`FILE_HASH` are unchanged by a
rename, so the post-migration scan re-analyses nothing.

## Steps

Set once:

```bash
export TALOSCONFIG=../infra/.generated/prod/talosconfig
export NODE=$(kubectl -n prd-platypod get pod -l app=komga -o jsonpath='{.items[0].spec.nodeName}')
export DB=/var/local/platypod/volumes/config/komga/config/database.sqlite
```

### 1. Stop Komga (so SQLite is quiescent and the WAL is checkpointed)

```bash
kubectl -n prd-platypod scale deploy/komga --replicas=0
```

Wait for the pod to be gone before continuing — a copy taken while Komga is
running is *not* consistent (`database disk image is malformed`; the live WAL
holds ~4.6 MB of uncommitted pages).

```bash
kubectl -n prd-platypod wait --for=delete pod -l app=komga --timeout=120s
```

### 2. Back up the database off the node

```bash
talosctl -n "$NODE" cp "$DB" ./database.sqlite.bak
sqlite3 ./database.sqlite.bak 'PRAGMA integrity_check;'   # must print: ok
```

Do not continue until `integrity_check` prints `ok`. This file is the rollback.

### 3. Move the folder on the NAS

Same volume, so this is a `rename(2)` — instant, no copying of the 116 GB.

```bash
mv /volume1/kubernetes/media/manga/bd /volume1/kubernetes/media/bd
chmod 2777 /volume1/kubernetes/media/bd     # match books/anime/movies/series
```

Run this **on the Synology** (or as root), not from the laptop: renaming `bd`
needs write on `manga/`, which is exactly the permission you don't have. The
`chmod` is what actually fixes laptop management — it puts `bd` on the same
`other=rwx` footing as every sibling folder.

### 4. Rewrite the paths

```bash
cp ./database.sqlite.bak ./database.sqlite.new
sqlite3 ./database.sqlite.new <<'SQL'
BEGIN;
UPDATE LIBRARY SET ROOT = 'file:/data/bd/'  WHERE ROOT = 'file:/data/manga/bd/';
UPDATE SERIES  SET URL  = 'file:/data/bd/' || substr(URL, length('file:/data/manga/bd/') + 1)
  WHERE URL LIKE 'file:/data/manga/bd/%';
UPDATE BOOK    SET URL  = 'file:/data/bd/' || substr(URL, length('file:/data/manga/bd/') + 1)
  WHERE URL LIKE 'file:/data/manga/bd/%';
COMMIT;
SQL
```

The URLs are percent-encoded `file:` URIs, but the prefix itself contains no
character that gets encoded, so a plain prefix swap is exact.

### 5. Verify before putting it back

```bash
sqlite3 ./database.sqlite.new <<'SQL'
PRAGMA integrity_check;
SELECT 'stale', COUNT(*) FROM BOOK   WHERE URL LIKE 'file:/data/manga/bd/%';   -- expect 0
SELECT 'stale', COUNT(*) FROM SERIES WHERE URL LIKE 'file:/data/manga/bd/%';   -- expect 0
SELECT 'books',  COUNT(*) FROM BOOK   WHERE URL LIKE 'file:/data/bd/%';        -- expect 954
SELECT 'series', COUNT(*) FROM SERIES WHERE URL LIKE 'file:/data/bd/%';        -- expect 62
SELECT 'root',   ROOT FROM LIBRARY WHERE NAME = 'bd';                          -- file:/data/bd/
SELECT 'progress', COUNT(*) FROM READ_PROGRESS;                                -- expect 39
SQL
```

All six must match before step 6. If any don't, stop — nothing has been written
back yet, so there is nothing to undo.

### 6. Put it back and restart

```bash
talosctl -n "$NODE" cp ./database.sqlite.new "$DB"
kubectl -n prd-platypod scale deploy/komga --replicas=1
```

### 7. Confirm in Komga

Library `bd` → 62 series, 954 books, covers intact, and a partially-read album
still shows its page. Trigger a scan and re-check the counts: a scan that finds
the paths valid adds and removes nothing.

## Rollback

Any failure after step 6:

```bash
kubectl -n prd-platypod scale deploy/komga --replicas=0
kubectl -n prd-platypod wait --for=delete pod -l app=komga --timeout=120s
talosctl -n "$NODE" cp ./database.sqlite.bak "$DB"
mv /volume1/kubernetes/media/bd /volume1/kubernetes/media/manga/bd   # on the NAS
git revert <the values commit>                                       # then let Flux reconcile
kubectl -n prd-platypod scale deploy/komga --replicas=1
```

The folder move and the DB rewrite must be rolled back **together** — the DB
backup points at `/data/manga/bd`, so the folder has to go back with it.

## What this does not fix

- `manga/mangas` stays `1000:1000 0755`, i.e. still not laptop-writable. It is
  Suwayomi's own directory and Suwayomi re-asserts ownership on every restart,
  so it should be managed through Suwayomi, not the Finder.
- comix-downloader writes into `manga/mangas` too — two downloaders sharing one
  directory, with the loser's `chgrp`/`chmod` undone on each Suwayomi restart.
  Untangling that is the separate, larger change (give manga a real library
  directory of its own, outside any app's download root).
