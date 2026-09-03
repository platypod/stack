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
  [`komga` in media.yaml](../../apps/base/values/media.yaml) declares the roots
  (`bd`, `manga`); the **komga-setup** Job creates any that don't exist yet.
- **Setup:** [komga-setup](komga-setup-job.md).
