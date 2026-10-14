#!/bin/bash
# ArgoCD's selfHeal (kagent Application) reverts these live patches on every
# sync despite ignoreDifferences + RespectIgnoreDifferences=true — observed
# not to hold on ArgoCD v3.0.6 for Deployment arg arrays / ConfigMap data
# fields under ServerSideApply. Root cause not fully diagnosed; this script
# re-applies both patches in one shot, idempotently. Run it any time
# kagent-grafana-mcp starts rejecting requests with "forbidden: host not
# allowed" or observability-agent/promql-agent start guessing datasource
# UIDs again.
set -euo pipefail
cd "$(dirname "$0")"

ALLOWED_HOSTS_ARG='-allowed-hosts=kagent-grafana-mcp.kagent:8000,kagent-grafana-mcp.kagent.svc:8000,kagent-grafana-mcp.kagent.svc.cluster.local:8000'
CURRENT_ARGS=$(kubectl get deployment kagent-grafana-mcp -n kagent -o jsonpath='{.spec.template.spec.containers[0].args}')
if [[ "$CURRENT_ARGS" != *"allowed-hosts"* ]]; then
  kubectl patch deployment kagent-grafana-mcp -n kagent --type='json' \
    -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"$ALLOWED_HOSTS_ARG\"}]"
  kubectl rollout status deployment kagent-grafana-mcp -n kagent --timeout=60s
else
  echo "kagent-grafana-mcp: -allowed-hosts already present, skipping"
fi

./apply-builtin-prompts-patch.sh
