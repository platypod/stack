{{/*
All three helpers below are generated off the single source of truth at
values/default/security/access-groups.yaml (`security.accessGroups` +
`security.categories`) — see that file's header for the full field reference.
A new tool/role/category only needs an entry there; nothing here should need
to change to pick it up.
*/}}

{{/*
Every LLDAP group name the seed job should create: "<tool>_<role>" for each
tool's declared roles, "<category>_user" for every category, "<category>_admin"
only where security.categories.<name>.admin is true, plus the two standing
groups ("admins", the global superuser; "lldap_strict_readonly", LLDAP's
built-in read-only group used by a few service-account binds).

Call with the root context: {{ include "security.allGroupNames" . }}
Returns an already-JSON-serialized array (the caller doesn't need to toJson it).
*/}}
{{- define "security.allGroupNames" -}}
{{- $groups := list "admins" "lldap_strict_readonly" -}}
{{- range $tool, $cfg := .Values.security.accessGroups -}}
{{- range $role := $cfg.roles -}}
{{- $groups = append $groups (printf "%s_%s" $tool $role) -}}
{{- end -}}
{{- end -}}
{{- range $cat, $catCfg := .Values.security.categories -}}
{{- $groups = append $groups (printf "%s_user" $cat) -}}
{{- if $catCfg.admin -}}
{{- $groups = append $groups (printf "%s_admin" $cat) -}}
{{- end -}}
{{- end -}}
{{- $groups | toJson -}}
{{- end -}}

{{/*
The Authelia access_control `subject` list for one tool: its own role groups
("<tool>_<role>" for each role it declares), the "<category>_user"/"_admin"
composite for every category it belongs to, and "admins".

Call with a dict {root: $, tool: "<toolKey>"}:
  {{ include "security.toolSubjects" (dict "root" $ "tool" "sonarr") }}
Returns an already-JSON-serialized array of "group:xxx" strings.
*/}}
{{- define "security.toolSubjects" -}}
{{- $root := .root -}}
{{- $cfg := index $root.Values.security.accessGroups .tool -}}
{{- $subjects := list -}}
{{- range $role := $cfg.roles -}}
{{- $subjects = append $subjects (printf "group:%s_%s" $.tool $role) -}}
{{- end -}}
{{- range $cat := $cfg.categories -}}
{{- $catCfg := index $root.Values.security.categories $cat -}}
{{- $subjects = append $subjects (printf "group:%s_user" $cat) -}}
{{- if $catCfg.admin -}}
{{- $subjects = append $subjects (printf "group:%s_admin" $cat) -}}
{{- end -}}
{{- end -}}
{{- $subjects = append $subjects "group:admins" -}}
{{- $subjects | toJson -}}
{{- end -}}

{{/*
The list of hostnames one tool's Authelia rule should gate: an explicit
`cfg.host` override if set, else `<valuesPath-or-toolKey>.host` from that
tool's own values block, plus any `cfg.extraHosts`. Every entry is a raw
`{{ }}`-templated string (same convention as every `host:` value in this
repo) — each is `tpl`-rendered here, so the caller gets plain strings back.

Call with a dict {root: $, tool: "<toolKey>"}:
  {{ include "security.toolHosts" (dict "root" $ "tool" "bookstack-db") }}
Returns an already-JSON-serialized array of hostnames.
*/}}
{{- define "security.toolHosts" -}}
{{- $root := .root -}}
{{- $cfg := index $root.Values.security.accessGroups .tool -}}
{{- $hosts := list -}}
{{- if $cfg.host -}}
{{- $hosts = append $hosts (tpl $cfg.host $root) -}}
{{- else -}}
{{- $path := $cfg.valuesPath | default .tool -}}
{{- $val := $root.Values -}}
{{- range splitList "." $path -}}
{{- $val = index $val . -}}
{{- end -}}
{{- $hosts = append $hosts (tpl $val.host $root) -}}
{{- end -}}
{{- range $extra := $cfg.extraHosts -}}
{{- $hosts = append $hosts (tpl $extra $root) -}}
{{- end -}}
{{- $hosts | toJson -}}
{{- end -}}
