# lldap-seed (Job)

Post-install/upgrade hook that pre-creates LLDAP groups and users via the LLDAP
REST/GraphQL API.

- **Template:** `src/security/templates/lldap/lldap--seed-job.yaml`
- **Image:** `python:3-alpine`.
- **Idempotent:** skips groups/users that already exist. A user's `password` is
  re-applied on every run when the entry has one; an entry **without** a `password`
  key never has its password touched (for hand-created users recorded only for
  their groups). Group names may also be pre-existing ones, not just generated.
- **Source of truth:** `lldap.seed.{groups,users}`. **Prod uses `platypod-sops`'s `clusters/prd/secrets.enc.yaml`**
  (the default seed in `apps/base/values/security.yaml` is fully overridden in prod), where the
  `otel-telemetry` service account is defined for the OTLP Basic-auth path.

See [lldap](lldap.md).
