# redis (dev-tools)

Redis backing [outline](outline.md) (cache + websocket/pub-sub).

- **Image:** `redis:7-alpine` (pinned).
- **Scope:** internal only (ClusterIP); dedicated to Outline.

Stock Redis; no persistence tuning beyond defaults.
