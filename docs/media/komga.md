# komga (media)

Comics/manga server (JVM-based).

- **Image:** `gotson/komga:1.24.4` (pinned).
- **Status:** currently **disabled** (`enable: false`) — Kavita + Suwayomi cover the
  use case now. Kept as the JVM fallback that was used while Kavita (.NET) was
  SIGILL-crashing on ARM. See [[kavita-sigill-use-komga]].
- **Storage:** library on NFS `media`; config/SQLite on the local `config` volume.
