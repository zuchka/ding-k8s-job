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
Resolve the workload image (with sentinel rejection).
Sentinel defaults in values.yaml are required because empty strings break
helm lint, and helm's `required` directive only emits a warning. We strip
sentinels ("REQUIRED-...") to empty, then `fail` if still empty.

When BOTH repo and tag are at sentinel defaults AND command is empty, we emit a
placeholder image string instead of failing — that combination signals "user
hasn't configured anything yet" (e.g. `helm lint .`). This keeps lint output
parseable. Real installs always set at least one real value, which trips the
fail path.
*/}}
{{- define "ding-k8s-job.workloadImage" -}}
{{- $repo := regexReplaceAll "^REQUIRED-.*$" .Values.image.repository "" -}}
{{- $tag := regexReplaceAll "^REQUIRED-.*$" .Values.image.tag "" -}}
{{- $unconfigured := and (not $repo) (and (not $tag) (empty .Values.command)) -}}
{{- if $unconfigured -}}
{{- printf "PLACEHOLDER-set-image-repository-and-tag:PLACEHOLDER" -}}
{{- else -}}
{{- if not $repo -}}{{- fail "image.repository is required (the workload image to wrap)" -}}{{- end -}}
{{- if not $tag -}}{{- fail "image.tag is required (no `latest` default to prevent footguns)" -}}{{- end -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}

{{/*
Render-time validation. Called from configmap.yaml so it runs once per render
regardless of which other templates render. Fails with clear messages.

Skips entirely when both image.repository and image.tag are at sentinel defaults
AND command is empty — that combination signals "user hasn't configured anything"
(e.g. `helm lint .` with stock defaults). In that case we let workloadImage in
podSpec be the gating fail point at install time.
*/}}
{{- define "ding-k8s-job.validate" -}}
{{- $repo := regexReplaceAll "^REQUIRED-.*$" .Values.image.repository "" -}}
{{- $tag := regexReplaceAll "^REQUIRED-.*$" .Values.image.tag "" -}}
{{- $unconfigured := and (not $repo) (and (not $tag) (empty .Values.command)) -}}
{{- if not $unconfigured -}}
{{- if not $repo -}}
{{- fail "image.repository is required (the workload image to wrap)" -}}
{{- end -}}
{{- if not $tag -}}
{{- fail "image.tag is required (no `latest` default to prevent footguns)" -}}
{{- end -}}
{{- if empty .Values.command -}}
{{- fail "command is required (the workload command DING will wrap)" -}}
{{- end -}}
{{- if and (ne .Values.kind "Job") (ne .Values.kind "CronJob") -}}
{{- fail (printf "kind must be Job or CronJob, got: %s" .Values.kind) -}}
{{- end -}}
{{- if and .Values.slack.webhookUrl .Values.existingSecret -}}
{{- fail "slack.webhookUrl and existingSecret are mutually exclusive — pick one" -}}
{{- end -}}
{{- if and .Values.slack.webhookUrl (hasKey .Values.extraNotifiers "slack") -}}
{{- fail "extraNotifiers.slack collides with the chart-managed slack notifier — use one or the other" -}}
{{- end -}}
{{- end -}}
{{- end -}}

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
      image: {{ include "ding-k8s-job.workloadImage" . }}
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
