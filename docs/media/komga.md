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

  | Library | Root | Written by |
  |---|---|---|
  | `bds` | `/data/bds` | by hand, from the laptop |
  | `mangas` | `/data/mangas` | Suwayomi (and comix-downloader, when enabled) |
  | `ebooks` | `/data/books` | Readarr/Bookshelf |

  `bds` and `mangas` are siblings at the top level of the share, and neither
  sits inside a service's working directory — see
  [comics-layout-migration](comics-layout-migration.md) for why that matters and
  how they got there.

- **Changing a library root is destructive.** Komga stores absolute per-book
  paths and deletes books it can't find on scan, and the setup Job is
  create-if-missing *by name* so it will never re-point an existing library.
  Editing a root in Git is therefore a no-op on a live instance, and doing it in
  the UI loses the library unless the new path is a parent of the old one —
  migrate with [comics-layout-migration](comics-layout-migration.md) instead.
- **Setup:** [komga-setup](komga-setup-job.md).
