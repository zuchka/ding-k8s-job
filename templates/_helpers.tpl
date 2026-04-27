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
spec:
  restartPolicy: {{ .Values.restartPolicy }}
  terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
  volumes:
    - name: ding-bin
      emptyDir: {}
    - name: ding-config
      configMap:
        name: {{ include "ding-k8s-job.fullname" . }}-config
  initContainers:
    - name: install-ding
      image: {{ include "ding-k8s-job.dingImage" . }}
      imagePullPolicy: {{ .Values.ding.image.pullPolicy }}
      command: ["/bin/sh", "-c", "cp /ding /shared/ding"]
      volumeMounts:
        - name: ding-bin
          mountPath: /shared
  containers:
    - name: workload
      image: {{ printf "%s:%s" .Values.image.repository .Values.image.tag }}
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      command:
        {{- include "ding-k8s-job.workloadCommand" . | nindent 8 }}
      {{- with .Values.args }}
      args:
        {{- range . }}
        - {{ . | quote }}
        {{- end }}
      {{- end }}
      envFrom:
        - secretRef:
            name: {{ include "ding-k8s-job.fullname" . }}
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
      volumeMounts:
        - name: ding-bin
          mountPath: /shared
        - name: ding-config
          mountPath: /config
          readOnly: true
{{- end }}
