{{/*
Expand the name of the chart.
*/}}
{{- define "backend-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "backend-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "backend-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "backend-api.labels" -}}
helm.sh/chart: {{ include "backend-api.chart" . }}
{{ include "backend-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "backend-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "backend-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "backend-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret containing app secrets.
Uses existingSecret if provided, otherwise a chart-managed Secret.
*/}}
{{- define "backend-api.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{ .Values.secrets.existingSecret }}
{{- else -}}
{{ include "backend-api.fullname" . }}
{{- end -}}
{{- end }}

{{/*
Postgres service name (used only when postgres.enabled).
*/}}
{{- define "backend-api.postgresFullname" -}}
{{ printf "%s-postgres" (include "backend-api.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Computed DATABASE_URL (only used when chart creates the secret AND postgres.enabled).
*/}}
{{- define "backend-api.databaseUrl" -}}
{{- if .Values.secrets.databaseUrl -}}
{{ .Values.secrets.databaseUrl }}
{{- else if .Values.postgres.enabled -}}
{{- printf "postgresql://%s:%s@%s:5432/%s?schema=public"
    .Values.postgres.auth.username
    .Values.postgres.auth.password
    (include "backend-api.postgresFullname" .)
    .Values.postgres.auth.database -}}
{{- else -}}
{{- fail "secrets.databaseUrl must be set when postgres.enabled=false and secrets.create=true" -}}
{{- end -}}
{{- end }}
