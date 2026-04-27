{{/*
Expand the name of the chart.
*/}}
{{- define "ding-k8s-job.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name. Truncated to 63 chars per K8s naming.
*/}}
{{- define "ding-k8s-job.fullname" -}}
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
Common labels applied to every rendered object.
*/}}
{{- define "ding-k8s-job.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "ding-k8s-job.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — used in label selectors and pod template metadata.
*/}}
{{- define "ding-k8s-job.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ding-k8s-job.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Resolve DING image — falls back to .Chart.AppVersion if ding.image.tag is empty.
*/}}
{{- define "ding-k8s-job.dingImage" -}}
{{- printf "%s:%s" .Values.ding.image.repository (default .Chart.AppVersion .Values.ding.image.tag) }}
{{- end }}

{{/*
Workload command — wraps user's command with `ding run --`.
*/}}
{{- define "ding-k8s-job.workloadCommand" -}}
- /shared/ding
- run
- --config
- /config/ding.yaml
- --
{{- range .Values.command }}
- {{ . | quote }}
{{- end }}
{{- end }}

{{/*
Pod spec template — shared between Job and CronJob.
Renders volumes, initContainers (DING-copy), workload container with downward API,
envFrom, command wrapping, and config-mount.
*/}}
{{- define "ding-k8s-job.podSpec" -}}
metadata:
  labels:
    {{- include "ding-k8s-job.selectorLabels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.podAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  restartPolicy: {{ .Values.restartPolicy }}
  terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
  {{- with .Values.serviceAccountName }}
  serviceAccountName: {{ . }}
  {{- end }}
  {{- with .Values.priorityClassName }}
  priorityClassName: {{ . }}
  {{- end }}
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumes:
    - name: ding-bin
      emptyDir: {}
    - name: ding-config
      configMap:
        name: {{ include "ding-k8s-job.fullname" . }}-config
    {{- with .Values.extraVolumes }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  initContainers:
    - name: install-ding
      image: {{ include "ding-k8s-job.dingImage" . }}
      imagePullPolicy: {{ .Values.ding.image.pullPolicy }}
      command: ["/bin/sh", "-c", "cp /ding /shared/ding"]
      {{- with .Values.dingResources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      volumeMounts:
        - name: ding-bin
          mountPath: /shared
  containers:
    - name: workload
      image: {{ required "image.repository is required (the workload image to wrap)" .Values.image.repository }}:{{ required "image.tag is required (no `latest` default to prevent footguns)" .Values.image.tag }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- with .Values.containerSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      command:
        {{- include "ding-k8s-job.workloadCommand" . | nindent 8 }}
      {{- with .Values.args }}
      args:
        {{- range . }}
        - {{ . | quote }}
        {{- end }}
      {{- end }}
      {{- /* envFrom priority: existingSecret > chart-managed slack Secret > none. Preserved from T4 — must remain conditional. */}}
      envFrom:
        {{- if .Values.existingSecret }}
        - secretRef:
            name: {{ .Values.existingSecret }}
        {{- else if .Values.slack.webhookUrl }}
        - secretRef:
            name: {{ include "ding-k8s-job.fullname" . }}
        {{- end }}
        {{- with .Values.extraEnvFrom }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      env:
        - name: POD_UID
          valueFrom:
            fieldRef:
              fieldPath: metadata.uid
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: JOB_NAME
          valueFrom:
            fieldRef:
              fieldPath: "metadata.labels['job-name']"
        {{- with .Values.extraEnv }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      volumeMounts:
        - name: ding-bin
          mountPath: /shared
        - name: ding-config
          mountPath: /config
          readOnly: true
        {{- with .Values.extraVolumeMounts }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
{{- end }}
