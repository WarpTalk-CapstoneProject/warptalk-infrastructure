{{- define "warptalk.labels" -}}
app.kubernetes.io/part-of: warptalk
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
