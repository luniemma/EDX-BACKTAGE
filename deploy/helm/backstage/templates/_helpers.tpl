{{/*
Expand the name of the chart.
*/}}
{{- define "backstage.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "backstage.fullname" -}}
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
{{- define "backstage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "backstage.labels" -}}
helm.sh/chart: {{ include "backstage.chart" . }}
{{ include "backstage.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "backstage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backstage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name
*/}}
{{- define "backstage.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "backstage.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the Secret containing app secrets.
Uses existingSecret if provided, otherwise a chart-managed Secret.
*/}}
{{- define "backstage.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{ .Values.secrets.existingSecret }}
{{- else -}}
{{ include "backstage.fullname" . }}
{{- end -}}
{{- end }}

{{/*
Postgres service name (used only when postgres.enabled).
*/}}
{{- define "backstage.postgresFullname" -}}
{{ printf "%s-postgres" (include "backstage.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Computed DATABASE_URL (only used when chart creates the secret AND postgres.enabled).
*/}}
{{/*
Backstage takes discrete POSTGRES_* values (see app-config.production.yaml)
rather than a single connection URL, so these resolve host/user from either the
in-cluster Postgres or an external one (RDS).
*/}}
{{- define "backstage.postgresHost" -}}
{{- if .Values.externalPostgres.host -}}
{{ .Values.externalPostgres.host }}
{{- else if .Values.postgres.enabled -}}
{{ include "backstage.postgresFullname" . }}
{{- else -}}
{{- fail "Set externalPostgres.host, or enable the in-cluster postgres.enabled=true" -}}
{{- end -}}
{{- end }}

{{- define "backstage.postgresUser" -}}
{{- if .Values.externalPostgres.host -}}
{{ .Values.externalPostgres.user }}
{{- else -}}
{{ .Values.postgres.auth.username }}
{{- end -}}
{{- end }}
