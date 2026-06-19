# mediarvester (media)

**Custom** media-harvesting tool.

- **Image:** `ghcr.io/platypod/mediarvester:v1.0.0` — built to GHCR from `mediarvester/`
  at the repo root, pinned.
- **Storage:** operates against the NFS `media` share.

Rebuild/push with `make build IMAGE=mediarvester VERSION=vX.Y.Z`. The image source +
behaviour live in the `mediarvester/` project; this module just deploys it.
