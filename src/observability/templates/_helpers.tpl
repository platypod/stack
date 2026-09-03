{{/*
Comma-separated list of LLDAP group names that grant the Grafana dashboard
scope-shim's admin scope (see grafana_scope-shim/config-map.yaml's ADMIN_GROUPS
env var and docs/observability/dashboard-multitenancy.md): grafana's own
"_admin" group, every category it belongs to that actually has an admin tier,
and the global "admins" superuser.

Source of truth is apps/base/values/security.yaml's security.accessGroups, read directly
here rather than via the security chart's equivalent helpers
(security.toolSubjects et al) — Helm named templates aren't visible across
separate top-level charts, and this chart only ever needs it for one tool, so
duplicating the ~10 lines beats a cross-chart coupling. If grafana's entry
there ever changes shape (a new category, roles renamed), update this
alongside it.

Call with the root context: {{ include "observability.grafanaAdminGroups" . }}
*/}}
{{- define "observability.grafanaAdminGroups" -}}
{{- $cfg := .Values.security.accessGroups.grafana -}}
{{- $groups := list -}}
{{- if has "admin" $cfg.roles -}}
{{- $groups = append $groups "grafana_admin" -}}
{{- end -}}
{{- range $cat := $cfg.categories -}}
{{- $catCfg := index $.Values.security.categories $cat -}}
{{- if $catCfg.admin -}}
{{- $groups = append $groups (printf "%s_admin" $cat) -}}
{{- end -}}
{{- end -}}
{{- $groups = append $groups "admins" -}}
{{- join "," $groups -}}
{{- end -}}
