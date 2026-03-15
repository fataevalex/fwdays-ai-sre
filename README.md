# fwdays-ai-sre

GitOps deployment of [kagent](https://kagent.dev) and [agentgateway](https://agentgateway.dev).

| Environment | Tool | Notes |
|---|---|---|
| **minipc** (homelab) | ArgoCD | ArgoCD pre-installed in cluster |
| **kind** (local/Codespaces) | Helm directly | No ArgoCD needed |

**LLM routing via agentgateway:** Ollama primary → Gemini 2.0 Flash Lite fallback.

## Architecture

```
minipc (ArgoCD):
  argocd/app-of-apps-minipc.yaml
    └── environments/minipc/kustomization.yaml
          ├── apps/agentgateway/overlays/minipc  → ArgoCD Applications + Gateway resources
          └── apps/kagent/overlays/minipc        → ArgoCD Applications + nginx ConfigMap

kind (Helm):
  Makefile targets
    ├── helm install agentgateway-crds + agentgateway  →  kubectl apply -k apps/agentgateway/overlays/kind
    └── helm install kagent-crds + kagent             →  kubectl apply -k apps/kagent/overlays/kind
```

## Prerequisites

- `kubectl`, `helm`, `kind`
- Gemini API key from [Google AI Studio](https://aistudio.google.com/)
- For minipc: `argocd` CLI, access to cluster via `~/.kube/minipc-k3s.yaml`

## Quick Start

### minipc homelab

```bash
cp .env.example .env
# edit .env → set GEMINI_API_KEY

make minipc-secrets    # create google-secret in cluster
make minipc-install    # apply ArgoCD app-of-apps
make minipc-status     # watch sync status
```

### kind (local dev / GitHub Codespaces)

```bash
cp .env.example .env
# edit .env → set GEMINI_API_KEY

make dev-up            # kind cluster + secrets + helm install everything
```

Services available at:
| Service | URL |
|---|---|
| kagent UI | http://localhost:8081 |
| agentgateway | http://localhost:8080 |

Tear down: `make dev-down`

### GitHub Codespaces

1. Set `GEMINI_API_KEY` in repo → Settings → Secrets → Codespaces
2. Open in Codespaces
3. Run `make dev-up`

## Makefile reference

```
make help                        # Show all targets

# minipc (ArgoCD)
make minipc-secrets              # Create Gemini secret in cluster
make minipc-install              # Deploy via ArgoCD app-of-apps
make minipc-uninstall            # Remove all apps
make minipc-sync-agentgateway    # Force sync agentgateway
make minipc-sync-kagent          # Force sync kagent
make minipc-status               # ArgoCD app status
make minipc-pods                 # Show pods
make minipc-logs-kagent          # Tail kagent controller logs
make minipc-logs-agentgateway    # Tail agentgateway logs

# kind (Helm)
make kind-up                     # Create kind cluster
make kind-down                   # Delete kind cluster
make kind-secrets                # Create Gemini secret in kind
make kind-install-agentgateway   # Helm install agentgateway
make kind-install-kagent         # Helm install kagent
make kind-install                # Helm install all
make kind-uninstall              # Helm uninstall all
make kind-pods                   # Show pods in kind
make kind-port-forward-kagent    # Port-forward kagent UI → :8081
make kind-port-forward-agentgateway  # Port-forward agentgateway → :8080

# Full dev workflow
make dev-up                      # kind-up + secrets + helm install
make dev-down                    # uninstall + kind-down
make dev-reset                   # dev-down + dev-up

# Validation & tests
make validate                    # kustomize build all overlays
make test-kagent                 # Query k8s-agent
make test-agentgateway           # Query agentgateway LLM
```

## Secrets

Not stored in git. Created out-of-band:

```bash
# minipc
GEMINI_API_KEY=your-key make minipc-secrets

# kind
GEMINI_API_KEY=your-key make kind-secrets
```

## Repository structure

```
├── apps/
│   ├── agentgateway/
│   │   ├── base/              # ArgoCD Applications (CRDs + chart)
│   │   └── overlays/
│   │       ├── minipc/        # nodeSelector + Gemini secret + Gateway resources
│   │       └── kind/          # Gateway resources only (no ArgoCD, no nodeSelector)
│   └── kagent/
│       ├── base/              # ArgoCD Applications + nginx ConfigMap
│       │   └── kustomize-patch/   # wave-3 Deployment patch for nginx mount
│       └── overlays/
│           ├── minipc/        # nodeSelector for all sub-charts
│           └── kind/          # nginx ConfigMap + deployment patch (no ArgoCD)
├── argocd/
│   └── app-of-apps-minipc.yaml
├── environments/
│   └── minipc/                # kustomize entry point for minipc
├── scripts/
│   ├── create-secrets.sh
│   ├── helm-values-agentgateway-kind.yaml
│   └── helm-values-kagent-kind.yaml
├── kind/cluster.yaml
├── .devcontainer/             # GitHub Codespaces
└── Makefile
```

## Testing

```bash
# Test kagent k8s-agent (minipc)
make test-kagent

# Test with kind
KAGENT_HOST=http://localhost:8081 make test-kagent

# Direct A2A call
curl -s https://kagent.local/a2a/kagent/k8s-agent -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"message/stream","params":{"message":{"role":"user","parts":[{"kind":"text","text":"List all namespaces"}]}},"id":"1"}'
```
