#!/usr/bin/env bash
set -euo pipefail

# Install kind
KIND_VERSION="v0.27.0"
echo "==> Installing kind ${KIND_VERSION}..."
curl -sLo /usr/local/bin/kind \
  "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x /usr/local/bin/kind

# Setup .env if not present
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "==> Created .env from .env.example"
fi

# If GEMINI_API_KEY is set via Codespaces secret, inject it into .env
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  sed -i "s|your-google-ai-studio-key-here|${GEMINI_API_KEY}|" .env
  echo "==> GEMINI_API_KEY injected from Codespaces secret"
fi

echo ""
echo "==> Dev environment ready. Next steps:"
echo "    1. Edit .env and set GEMINI_API_KEY (if not set via Codespaces secrets)"
echo "    2. make dev-up"
