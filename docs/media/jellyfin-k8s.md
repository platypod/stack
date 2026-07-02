# jellyfin-k8s (media)

In-cluster Jellyfin, deployed **only to compare against the host-native
`jellyfin-proxy` instance via [jellyswarrm](jellyswarrm.md)**. Not a permanent
media path — no ingress, no Jellyseerr/Homepage wiring.

- **Enabled:** prod only (`values/prd/values.yaml` → `jellyfinK8s.enable`).
- **Image:** `jellyfin/jellyfin:latest` (same as `jellyfin`).
- **Storage:** same NFS `media` PVC as `jellyfin-proxy`, mounted **read-only**
  at `/media` — same content is required for the comparison to mean anything.
  Config on the local `config` volume (`storage.defaultVolumes.config`, subPath
  `jellyfin-k8s`) — NOT the NFS `apps` volume the base `jellyfin` chart's `pvc`
  field points at, which would hit the SQLite-on-NFS problem (see
  [stack/CLAUDE.md](../../CLAUDE.md)).
- **No GPU passthrough.** Runs inside the Talos VM guest — expected to lose any
  transcode-performance comparison against `jellyfin-proxy` for hardware
  reasons, not virtualization ones. Scope the comparison to direct-play and API
  latency (library scan time, browse/API response, direct-play startup and
  throughput) if that's the actual question.
- **Setup:** `jellyfin-k8s-setup` Job creates the admin user only (no API-key
  handoff — this instance isn't a Homepage/Jellyseerr backend).
- **Still manual:** add its library folders in the Jellyfin admin UI (point at
  subfolders under `/media`) — Jellyfin itself has no declarative way to seed
  library definitions, unlike jellyswarrm's backend list (see
  [jellyswarrm.md](jellyswarrm.md)), which is seeded automatically.
