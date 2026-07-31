{{/*
Whether at least one Minecraft instance is enabled. mc-router (Deployment,
Service, RBAC) only needs to exist when there's something for it to route to —
this keeps "enable an instance" the only knob, instead of a second toggle that
can drift out of sync with the instances map.

Call with the root context, e.g.:
  {{- if eq (include "games.minecraft.anyEnabled" .) "true" }}
*/}}
{{- define "games.minecraft.anyEnabled" -}}
{{- $anyEnabled := false -}}
{{- range $name, $instance := .Values.minecraft.instances -}}
{{- if $instance.enable -}}
{{- $anyEnabled = true -}}
{{- end -}}
{{- end -}}
{{- $anyEnabled -}}
{{- end -}}
