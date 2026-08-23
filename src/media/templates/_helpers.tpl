{{/*
TCP startup + liveness probes for the *arr apps (sonarr/radarr/prowlarr/readarr/
bazarr). These LinuxServer images keep the container alive even when the .NET app
fails to start (it parks at "waiting for user intervention"), so without a probe a
dead app stays Running and the ingress returns 502. The kubelet can't see the
ingress 502 — the pod-level equivalent is "the port refuses connections", which a
TCP-socket probe detects. We avoid an HTTP /ping probe because that endpoint
returns 500 while the DB is still migrating on a cold start.

Call with the container port as the context, e.g.:
  {{- include "media.netProbes" .Values.sonarr.ports.http.targetPort | nindent 8 }}

The startupProbe gives the app up to 5 min (30 × 10s) to bind its port — covering
slow DB migrations — before the livenessProbe takes over and restarts a hung app.
*/}}
{{- define "media.netProbes" -}}
startupProbe:
  tcpSocket:
    port: {{ . }}
  periodSeconds: 10
  failureThreshold: 30
livenessProbe:
  tcpSocket:
    port: {{ . }}
  periodSeconds: 20
  timeoutSeconds: 5
  failureThreshold: 3
{{- end -}}

{{/*
Comma-separated list of LLDAP group names that grant Mediarvester's in-app
admin role (mediarvester/src/api/deps.py's ADMIN_GROUPS env var): the tool's
own "_admin" group, every category it belongs to that actually has an admin
tier, and the global "admins" superuser.

Source of truth is values/default/security/access-groups.yaml, read directly
here rather than via the security chart's equivalent helpers
(security.toolSubjects et al) — Helm named templates aren't visible across
separate top-level charts, and this chart only ever needs it for one tool, so
duplicating the ~10 lines beats a cross-chart coupling. If mediarvester's
entry there ever changes shape (a new category, roles renamed), update this
alongside it.

Call with the root context: {{ include "media.mediarvesterAdminGroups" . }}
*/}}
{{- define "media.mediarvesterAdminGroups" -}}
{{- $cfg := .Values.security.accessGroups.mediarvester -}}
{{- $groups := list -}}
{{- if has "admin" $cfg.roles -}}
{{- $groups = append $groups "mediarvester_admin" -}}
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
