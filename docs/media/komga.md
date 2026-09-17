# komga (media)

Comics/manga server (JVM-based).

- **Image:** `gotson/komga:1.25.0` (pinned).
- **Status:** currently **enabled** (`enable: true`) and the active comics/manga
  reader — Kavita (.NET) SIGILL-crashes on the ARM guest, so the stack reverted
  to Komga (JVM, unaffected). See [kavita](kavita.md).
- **Storage:** library on NFS `media`; config/SQLite on the local `config` volume.
- **Libraries:** each library's root must contain one subfolder per Series —
  books sitting directly in the root all collapse into a single series named
  after the root folder. `komga.libraries` in
  [`komga` in media.yaml](../../apps/base/values/media.yaml) declares the roots;
  the **komga-setup** Job creates any that don't exist yet.

  | Library | Root | Owned by |
  |---|---|---|
  | `bd` | `/data/bd` | managed by hand (top-level media folder) |
  | `manga` | `/data/manga/mangas` | **Suwayomi** — its download root's own `mangas/` dir |
  | `ebooks` | `/data/books` | Readarr/Bookshelf |

  `bd` is deliberately *not* under `manga/`: that folder belongs to Suwayomi,
  which `chown -R`s it on every pod start. See
  [bd-library-move](bd-library-move.md) for the migration that moved it out.

- **Changing a library root is destructive.** Komga stores absolute per-book
  paths and deletes books it can't find on scan, and the setup Job is
  create-if-missing *by name* so it will never re-point an existing library.
  Editing a root in Git is therefore a no-op on a live instance, and doing it in
  the UI loses the library unless the new path is a parent of the old one —
  migrate with [bd-library-move](bd-library-move.md) instead.
- **Setup:** [komga-setup](komga-setup-job.md).
