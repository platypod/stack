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
