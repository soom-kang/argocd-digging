{{- define "multi-source-demo.name" -}}
multi-source-demo
{{- end -}}

{{- define "multi-source-demo.fullname" -}}
{{- .Release.Name -}}
{{- end -}}
