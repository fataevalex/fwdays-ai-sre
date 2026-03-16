#!/usr/bin/env bash
# Waits for kind cluster to be ready and starts port-forwards for Codespaces
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-kubeconfig-kind.yaml}"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "==> No kubeconfig found, skipping port-forwards (run make dev-up first)"
  exit 0
fi

echo "==> Waiting for kagent-ui to be ready..."
kubectl --kubeconfig "$KUBECONFIG" wait deployment/kagent-ui \
  -n kagent --for=condition=Available --timeout=120s 2>/dev/null || {
  echo "==> kagent-ui not ready, skipping port-forwards"
  exit 0
}

echo "==> Starting port-forwards..."
KUBECONFIG="$KUBECONFIG" kubectl port-forward svc/kagent-ui \
  -n kagent 8081:8080 --address=0.0.0.0 &
KUBECONFIG="$KUBECONFIG" kubectl port-forward svc/agentgateway-proxy \
  -n agentgateway-system 8080:8080 --address=0.0.0.0 &

echo "==> Port-forwards started:"
echo "    kagent UI:    http://localhost:8081"
echo "    agentgateway: http://localhost:8080"
