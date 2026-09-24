{{- define "warptalk.labels" -}}
app.kubernetes.io/part-of: warptalk
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- /*
The UID a workload's image runs as. One answer for the pod and the container: the two levels used
to be written out separately and disagreed - metrics-exporter ran with pod runAsUser 999 and
container runAsUser 65534, because the container branch tested the "-exporter" suffix first.
  * warptalk-ai images: `useradd -r worker` -> 999
  * warptalk-web: USER node -> 1000
  * .NET images: $APP_UID -> 1654
A workload can still override it with runAsUser/runAsGroup.
Call with (dict "name" $name "app" $app).
*/ -}}
{{- define "warptalk.runAsUser" -}}
{{- if .app.runAsUser -}}
{{ .app.runAsUser }}
{{- else if or (hasSuffix "-worker" .name) (eq .name "metrics-exporter") -}}
999
{{- else if eq .name "frontend" -}}
1000
{{- else -}}
1654
{{- end -}}
{{- end }}

{{- define "warptalk.runAsGroup" -}}
{{- if .app.runAsGroup -}}
{{ .app.runAsGroup }}
{{- else -}}
{{ include "warptalk.runAsUser" . }}
{{- end -}}
{{- end }}

{{- /*
True when KEDA owns the replica count of this workload. KEDA creates its own HPA, so the
Deployment must not also carry `replicas`, or every `helm upgrade` resets it to the static value
and fights the autoscaler.
Call with (dict "name" $name "root" $).
*/ -}}
{{- define "warptalk.kedaManaged" -}}
{{- if and .root.Values.keda.enabled (hasKey .root.Values.keda.workers .name) -}}
true
{{- end -}}
{{- end }}

{{- /*
The replica floor a workload keeps during voluntary disruption: the autoscaler minimum when
something scales it, otherwise the static replica count. Singletons are always 1.
Call with (dict "name" $name "app" $app "root" $).
*/ -}}
{{- define "warptalk.minReplicas" -}}
{{- if .app.singleton -}}
1
{{- else if include "warptalk.kedaManaged" (dict "name" .name "root" .root) -}}
{{ index .root.Values.keda.workers .name "min" | int }}
{{- else if and .app.autoscaling .app.autoscaling.enabled -}}
{{ .app.autoscaling.min | int }}
{{- else -}}
{{ .app.replicas | int }}
{{- end -}}
{{- end }}

{{- /*
Node placement for application pods. Empty in the chart defaults (a kind or single-node cluster
has no role labels); the production values pin every app pod to the App node, and the data VM's
NoSchedule taint keeps them off it even if the selector were dropped.
*/ -}}
{{- define "warptalk.placement" -}}
{{- with .Values.placement.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.placement.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- /* The host every ${API_DOMAIN} URL in production compose is built from. */ -}}
{{- define "warptalk.apiHost" -}}
{{- .Values.global.apiDomain | default .Values.global.domain -}}
{{- end }}
