# fwdays-ai-sre

GitOps deployment of [kagent](https://kagent.dev) and [agentgateway](https://agentgateway.dev) via ArgoCD.

## Architecture

```
ArgoCD app-of-apps
  └── environments/<env>/kustomization.yaml
        ├── apps/agentgateway/overlays/<env>   → ArgoCD Applications (CRDs + chart + gateway)
        └── apps/kagent/overlays/<env>         → ArgoCD Applications (CRDs + chart + nginx patch)
```

**LLM routing:** Ollama (primary) → Gemini 2.0 Flash Lite (fallback) via agentgateway.

## Prerequisites

- `kubectl`, `kustomize`, `kind`, `argocd` CLI
- Gemini API key from [Google AI Studio](https://aistudio.google.com/)

## Quick Start

### Option 1 — minipc homelab cluster

```bash
# 1. Set Gemini API key secret in cluster
cp .env.example .env
# edit .env → set GEMINI_API_KEY
make bootstrap-secrets

# 2. Deploy via ArgoCD app-of-apps
make install-minipc

# 3. Watch status
make status
```

### Option 2 — local kind cluster

```bash
cp .env.example .env
# edit .env → set GEMINI_API_KEY

# Creates kind cluster + installs ArgoCD + secrets + deploys
make dev-up
```

Services available at:
| Service | URL |
|---|---|
| kagent UI | http://localhost:8081 |
| agentgateway | http://localhost:8080 |
| ArgoCD UI | http://localhost:8082 (run `make port-forward-argocd`) |

### Option 3 — GitHub Codespaces

1. Open repo in Codespaces
2. Set `GEMINI_API_KEY` in Codespaces Secrets (repo settings → Secrets and variables → Codespaces)
3. Run `make dev-up` in the terminal

## Makefile targets

```
make help                    # Show all targets
make dev-up                  # Full local setup (kind + ArgoCD + deploy)
make dev-down                # Tear down local setup
make install-minipc          # Deploy to minipc cluster
make bootstrap-secrets       # Create Gemini secret (minipc)
make bootstrap-secrets-kind  # Create Gemini secret (kind)
make sync-kagent             # Force sync kagent apps
make sync-agentgateway       # Force sync agentgateway apps
make validate                # Validate all kustomize overlays
make test-kagent             # Send test query to k8s-agent
make test-agentgateway       # Send test query to agentgateway
make status                  # Show ArgoCD app status
make pods                    # Show running pods
make logs-kagent             # Tail kagent controller logs
```

## Repository structure

```
├── apps/
│   ├── agentgateway/
│   │   ├── base/              # ArgoCD Applications + base resources
│   │   └── overlays/
│   │       ├── minipc/        # nodeSelector, Ollama host, Gemini secret
│   │       └── kind/          # no nodeSelector, host.docker.internal for Ollama
│   └── kagent/
│       ├── base/              # ArgoCD Applications + nginx ConfigMap
│       │   └── kustomize-patch/   # wave-3 Deployment patch for nginx mount
│       └── overlays/
│           ├── minipc/        # nodeSelector for all sub-charts
│           └── kind/          # NodePort UI service
├── argocd/                    # Root app-of-apps per environment
├── environments/              # Kustomize entry points (minipc / kind)
├── kind/                      # kind cluster config
├── scripts/                   # Bootstrap helpers
├── .devcontainer/             # GitHub Codespaces config
└── Makefile
```

## Secrets

Secrets are **not stored in git**. The `google-secret` (Gemini API key) is created out-of-band:

```bash
# minipc
GEMINI_API_KEY=your-key make bootstrap-secrets

# kind
GEMINI_API_KEY=your-key make bootstrap-secrets-kind
```

## Testing

```bash
# Test kagent k8s-agent
make test-kagent

# Test agentgateway LLM routing
make test-agentgateway

# Direct A2A call
curl -s https://kagent.local/a2a/kagent/k8s-agent -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"message/stream","params":{"message":{"role":"user","parts":[{"kind":"text","text":"List all namespaces"}]}},"id":"1"}'
```
