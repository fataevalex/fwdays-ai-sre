#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.14.2}"
KUBECONFIG="${KUBECONFIG:-kubeconfig-kind.yaml}"

echo "==> Installing ArgoCD ${ARGOCD_VERSION} into kind cluster..."
kubectl --kubeconfig "${KUBECONFIG}" create namespace argocd --dry-run=client -o yaml | \
  kubectl --kubeconfig "${KUBECONFIG}" apply -f -

kubectl --kubeconfig "${KUBECONFIG}" apply -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for ArgoCD to be ready..."
kubectl --kubeconfig "${KUBECONFIG}" wait --for=condition=available \
  deployment/argocd-server -n argocd --timeout=300s

echo "==> ArgoCD installed. Initial admin password:"
kubectl --kubeconfig "${KUBECONFIG}" -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "==> UI available at http://localhost:8082 (after: make port-forward-argocd)"
