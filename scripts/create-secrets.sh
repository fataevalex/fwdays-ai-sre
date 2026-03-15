#!/usr/bin/env bash
# Create required secrets in the target cluster.
# Reads GEMINI_API_KEY from environment or .env file.
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-~/.kube/minipc-k3s.yaml}"
ENV_FILE="${ENV_FILE:-.env}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a && source "${ENV_FILE}" && set +a
fi

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "ERROR: GEMINI_API_KEY is not set. Copy .env.example to .env and fill in the value."
  exit 1
fi

echo "==> Creating google-secret in agentgateway-system..."
kubectl --kubeconfig "${KUBECONFIG}" create namespace agentgateway-system \
  --dry-run=client -o yaml | kubectl --kubeconfig "${KUBECONFIG}" apply -f -

kubectl --kubeconfig "${KUBECONFIG}" create secret generic google-secret \
  -n agentgateway-system \
  --from-literal="Authorization=Bearer ${GEMINI_API_KEY}" \
  --dry-run=client -o yaml | kubectl --kubeconfig "${KUBECONFIG}" apply -f -

echo "==> Secret created successfully."
