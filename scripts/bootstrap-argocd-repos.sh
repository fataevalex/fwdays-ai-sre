#!/usr/bin/env bash
# Register OCI Helm repositories with ArgoCD.
# Required for ArgoCD versions that don't auto-discover OCI repos.
set -euo pipefail

ARGOCD_SERVER="${ARGOCD_SERVER:-localhost:8082}"
ARGOCD_USER="${ARGOCD_USER:-admin}"
ARGOCD_PASSWORD="${ARGOCD_PASSWORD:-}"

if [[ -z "${ARGOCD_PASSWORD}" ]]; then
  echo "ERROR: set ARGOCD_PASSWORD env var"
  exit 1
fi

argocd login "${ARGOCD_SERVER}" \
  --username "${ARGOCD_USER}" \
  --password "${ARGOCD_PASSWORD}" \
  --insecure

echo "==> Registering OCI Helm repos..."
argocd repo add oci://ghcr.io/kgateway-dev/charts \
  --type helm \
  --name agentgateway \
  --enable-oci \
  --insecure-skip-server-verification || true

argocd repo add oci://ghcr.io/kagent-dev/kagent/helm \
  --type helm \
  --name kagent \
  --enable-oci \
  --insecure-skip-server-verification || true

echo "==> Done. Repos registered:"
argocd repo list
