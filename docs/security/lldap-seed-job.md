# lldap-seed (Job)

Post-install/upgrade hook that pre-creates LLDAP groups and users via the LLDAP
REST/GraphQL API.

- **Template:** `src/security/templates/lldap/lldap--seed-job.yaml`
- **Image:** `python:3-alpine`.
- **Idempotent:** skips groups/users that already exist; passwords set **only on
  creation** (existing users keep theirs).
- **Source of truth:** `lldap.seed.{groups,users}`. **Prod uses `values/prd/values.yaml`**
  (the default `lldap.yaml` seed is fully overridden in prod), where the
  `otel-telemetry` service account is defined for the OTLP Basic-auth path.

See [lldap](lldap.md).
