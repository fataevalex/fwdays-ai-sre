#!/usr/bin/env bash
set -euo pipefail

# Install kind
KIND_VERSION="v0.27.0"
echo "==> Installing kind ${KIND_VERSION}..."
curl -sLo /usr/local/bin/kind \
  "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x /usr/local/bin/kind

# Install ArgoCD CLI
ARGOCD_VERSION="v2.14.2"
echo "==> Installing argocd CLI ${ARGOCD_VERSION}..."
curl -sLo /usr/local/bin/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
chmod +x /usr/local/bin/argocd

# Setup .env if not present
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "==> Created .env from .env.example"
fi

# If GEMINI_API_KEY is set via Codespaces secret, write it to .env
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  sed -i "s|your-google-ai-studio-key-here|${GEMINI_API_KEY}|" .env
  echo "==> GEMINI_API_KEY injected from Codespaces secret"
fi

echo ""
echo "==> Dev environment ready. Next steps:"
echo "    1. Edit .env and set GEMINI_API_KEY"
echo "    2. make dev-up"
