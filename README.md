# ding-k8s-job

> Helm chart for running Kubernetes Jobs and CronJobs with embedded [DING](https://github.com/zuchka/ding) alerting. Alert on non-zero exit out of the box.

`ding-k8s-job` collapses the [DING K8s recipe's](https://github.com/zuchka/ding/blob/main/docs/recipes/kubernetes-jobs.md) 93-line manifest into a one-line `helm install`. Wrapper-pattern only; works on Kubernetes 1.21+. Requires Helm 3.8+.

## Quick start (Slack, dev)

```bash
helm install nightly-batch oci://ghcr.io/zuchka/ding-k8s-job \
  --set image.repository=my-app \
  --set image.tag=v1.2.3 \
  --set command='{python,train.py}' \
  --set slack.webhookUrl=$SLACK_WEBHOOK_URL
```

What happens:
- A Job is created that wraps your workload's `command` with `ding run --`.
- A chart-managed Secret holds the Slack webhook URL.
- A ConfigMap holds the rendered `ding.yaml` with one Slack notifier and the default `job_failed` rule.
- When the workload exits non-zero, DING fires a Slack alert tagged with namespace, pod, node, job_name, and exit_code, then the Pod terminates cleanly.

## Production (PagerDuty + sealed-secrets)

Pre-provision a Secret containing your routing key:

```bash
kubectl create secret generic ding-prod-secrets \
  --from-literal=PAGERDUTY_ROUTING_KEY=R0123ABC...
```

Write your notifier YAML (`pagerduty.yaml`):

```yaml
pagerduty-prod:
  type: pagerduty
  routing_key: ${PAGERDUTY_ROUTING_KEY}
```

Write your rule YAML (`prod-rules.yaml`):

```yaml
- name: job_failed
  match:
    metric: run.exit
  condition: value != 0
  mode: end-of-run
  message: "{{ .pod }} (Job {{ .job_name }}) failed with exit {{ .exit_code }}"
  alert:
    - notifier: pagerduty-prod
```

Install:

```bash
helm install nightly-batch oci://ghcr.io/zuchka/ding-k8s-job \
  --set image.repository=my-app \
  --set image.tag=v1.2.3 \
  --set command='{python,train.py}' \
  --set existingSecret=ding-prod-secrets \
  --set-file extraNotifiers=./pagerduty.yaml \
  --set-file rules=./prod-rules.yaml
```

`--set-file` (not `--set`) ensures `${VAR}` references survive shell quoting.

## CronJob

```bash
helm install nightly-cron oci://ghcr.io/zuchka/ding-k8s-job \
  --set kind=CronJob \
  --set schedule='0 2 * * *' \
  --set image.repository=my-app \
  --set image.tag=v1.2.3 \
  --set command='{python,batch.py}' \
  --set slack.webhookUrl=$SLACK_WEBHOOK_URL
```

`concurrencyPolicy: Forbid` and history-limit defaults render automatically.

## Values reference

See [values.yaml](./values.yaml) for the full annotated set. Highlights:

| Value | Required? | Purpose |
|---|---|---|
| `image.repository` | Yes | Workload image (no `latest` default). Values starting with `REQUIRED-` or `PLACEHOLDER-` are reserved sentinel namespace and stripped by the chart at render — don't use those prefixes in your image names. |
| `image.tag` | Yes | Workload image tag (same sentinel-prefix rule applies). |
| `command` | Yes | Workload command — DING wraps with `run --` |
| `kind` | No (default `Job`) | `Job` or `CronJob` |
| `schedule` | If `kind=CronJob` | Cron expression |
| `slack.webhookUrl` | One of slack/existingSecret/none | Quick-start Slack via chart-managed Secret |
| `existingSecret` | One of slack/existingSecret/none | Production: pre-provisioned Secret |
| `extraNotifiers` | No | Arbitrary DING notifier YAML, merged into `notifiers:`. Accepts both inline objects and `--set-file path` strings. |
| `rules` | No (default `job_failed`) | Replaces default; full DING rules YAML. Accepts both inline arrays and `--set-file path` strings. |
| `ding.drainTimeout` | No (default `30s`) | DING shutdown drain budget |
| `terminationGracePeriodSeconds` | No (default `60`) | K8s SIGTERM grace; pair with `drainTimeout` |
| `nodeSelector`, `tolerations`, `affinity`, `resources` | No | Standard K8s scheduling escape hatches |
| `imagePullSecrets` | No | Private registry credentials |
| `serviceAccountName` | No (default `default`) | If your cluster needs RBAC for the workload |
| `extraEnv`, `extraEnvFrom`, `extraVolumes`, `extraVolumeMounts` | No | Append to workload's containers spec |

## Troubleshooting

**Alert doesn't fire.**
- Check `kubectl logs job/<release-name> -c workload` for DING's startup output.
- Confirm the Secret is readable by the default ServiceAccount (`kubectl auth can-i get secret/<release-name> --as=system:serviceaccount:<ns>:default`).
- If `existingSecret`, verify keys match what your `extraNotifiers` references (e.g., `${PAGERDUTY_ROUTING_KEY}` requires that exact key).

**Pod gets SIGKILL'd before alert reaches the wire.**
- `terminationGracePeriodSeconds` must exceed `drainTimeout`. Defaults (60s and 30s) are safe; if you tune one, tune both.
- Slack/PagerDuty default backoff is `1s, 2s, 4s` — full retry cycle is 7s. Set `drainTimeout` ≥ 10s.

**Default rule alerts go nowhere.**
- The default `job_failed` rule references the `slack` notifier. If you set `existingSecret` without `slack.webhookUrl`, no Slack notifier exists — provide your own `rules:` referencing your real notifier name.
- After `helm install`, check the rendered NOTES — both warnings ("No notifiers configured" / "Default rule alerts to slack but no Slack notifier is configured") fire when something's off.

**`message:` field shows up empty in alerts.**
- The chart escapes DING's `{{ }}` template syntax via backtick literals. If you customize the chart's templates and break the escape, `{{ .pod }}` will render as empty. Snapshot tests in `tests/` lock this in; don't disable them.

**`helm install demo .` (no flags) succeeds but Pod hits ImagePullBackOff.**
- The chart ships with sentinel image defaults so `helm lint` works without flags. Real installs must override `image.repository` and `image.tag`. The default ConfigMap renders an obvious placeholder; you'll see `image: PLACEHOLDER-set-image-repository-and-tag:PLACEHOLDER` in `kubectl describe pod`.

## How this chart relates to DING's K8s recipe

The [K8s recipe in the DING repo](https://github.com/zuchka/ding/blob/main/docs/recipes/kubernetes-jobs.md) is the unrolled equivalent of this chart. If you want fine-grained control over every K8s field, copy the recipe's manifest. If you want the one-line install, use this chart.

## Sidecar pattern

The recipe also documents a [sidecar pattern](https://github.com/zuchka/ding/blob/main/docs/recipes/kubernetes-jobs.md#sidecar-alternative-k8s-129) for K8s 1.29+ when the workload's container has a fixed entrypoint. This chart is wrapper-only; sidecar coverage may land in a future version if user demand emerges.

## License

[AGPL-3.0-or-later](./LICENSE) — same as DING.
