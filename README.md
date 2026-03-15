# fwdays-ai-sre

Lab-1: Basic Agentic Infrastructure deployment of [kagent](https://kagent.dev) and [agentgateway](https://agentgateway.dev).

| Environment | Tool | How |
|---|---|---|
| **podman** (local laptop) | podman compose | standalone agentgateway binary + kagent containers |
| **kind** (local / GitHub Codespaces) | Helm | direct Helm install, no ArgoCD |
| **minipc** (homelab k8s) | ArgoCD | app-of-apps GitOps |

**LLM:** Gemini 2.0 Flash Lite (podman/kind) · Ollama primary + Gemini fallback (minipc)

## Prerequisites

- `podman` + `podman compose` — for local laptop
- `kubectl`, `helm`, `kind` — for kind cluster
- Gemini API key from [Google AI Studio](https://aistudio.google.com/)

## Quick Start

### podman (local laptop)

```bash
cp .env.example .env
# edit .env → set GEMINI_API_KEY

make podman-up
```

| Service | URL |
|---|---|
| agentgateway LLM API | http://localhost:3000/v1 |
| agentgateway Admin UI | http://localhost:15000/ui/ |
| kagent UI | http://localhost:8080 |

```bash
make podman-test-agentgateway  # test LLM routing
make podman-test-kagent        # test k8s-agent
make podman-down               # stop
```

### kind (local dev / GitHub Codespaces)

```bash
cp .env.example .env
# edit .env → set GEMINI_API_KEY

make dev-up
```

| Service | URL |
|---|---|
| kagent UI | http://localhost:8081 (NodePort 30081) |
| agentgateway | http://localhost:8080 (NodePort 30080) |

```bash
make kind-port-forward-kagent        # or use NodePort directly
make kind-port-forward-agentgateway
make dev-down                        # tear down
```

### minipc homelab (ArgoCD)

```bash
make minipc-secrets    # create google-secret from .env
make minipc-install    # kubectl apply argocd/app-of-apps-minipc.yaml
make minipc-status     # watch ArgoCD sync
```

| Service | URL |
|---|---|
| agentgateway LLM API | http://192.168.0.253:8080/v1 |
| agentgateway Admin UI | http://192.168.0.253:8080/ui/ |
| kagent UI | https://kagent.local |
| kagent A2A | `kubectl port-forward svc/k8s-agent 8083:8080 -n kagent` → http://localhost:8083 |

### GitHub Codespaces

1. Set `GEMINI_API_KEY` in repo → Settings → Secrets → Codespaces
2. Open in Codespaces → `make dev-up`

## Makefile reference

```
make help                          # all targets

# podman (local laptop)
make podman-up                     # start all services
make podman-down                   # stop all services
make podman-pull                   # pre-pull images
make podman-status                 # show running containers
make podman-logs                   # tail all logs
make podman-logs-agentgateway      # tail agentgateway logs
make podman-logs-kagent            # tail kagent-controller logs
make podman-test-agentgateway      # test LLM API
make podman-test-kagent            # test kagent agent

# kind (no ArgoCD)
make dev-up                        # full setup: kind + secrets + helm install
make dev-down                      # tear down
make dev-reset                     # dev-down + dev-up
make kind-up / kind-down           # manage kind cluster
make kind-secrets                  # create Gemini secret
make kind-install                  # helm install everything
make kind-install-agentgateway     # helm install agentgateway only
make kind-install-kagent           # helm install kagent only
make kind-uninstall                # helm uninstall everything
make kind-pods                     # show pods
make kind-port-forward-kagent      # port-forward kagent → :8081
make kind-port-forward-agentgateway  # port-forward agentgateway → :8080

# minipc (ArgoCD)
make minipc-secrets                # create Gemini secret
make minipc-install                # deploy via ArgoCD app-of-apps
make minipc-uninstall              # remove apps
make minipc-sync                   # force sync fwdays-ai-sre-minipc app
make minipc-status                 # ArgoCD app status
make minipc-pods                   # show pods

# validation & tests
make validate                      # kustomize build all overlays
make test-kagent                   # test k8s-agent (set KAGENT_HOST)
make test-agentgateway             # test LLM routing (set AGENTGATEWAY_HOST)
```

## Repository structure

```
├── apps/
│   ├── agentgateway/
│   │   ├── base/              # ArgoCD Applications (CRDs + chart)
│   │   └── overlays/
│   │       ├── minipc/        # nodeSelector + Gemini secret + Gateway resources
│   │       └── kind/          # Gateway resources (no ArgoCD, no nodeSelector)
│   └── kagent/
│       ├── base/              # ArgoCD Applications + nginx ConfigMap
│       │   └── kustomize-patch/   # wave-3 Deployment patch for nginx mount
│       └── overlays/
│           ├── minipc/        # nodeSelector for all sub-charts
│           └── kind/          # nginx ConfigMap + deployment patch
├── argocd/
│   └── app-of-apps-minipc.yaml    # minipc only
├── environments/
│   └── minipc/                    # kustomize entry point for minipc
├── podman/
│   ├── compose.yaml               # podman compose: agentgateway + kagent
│   ├── config.yaml                # standalone agentgateway config
│   └── nginx.conf                 # kagent-ui nginx (proxies to controller container)
├── kind/
│   ├── cluster.yaml               # kind cluster config
│   └── helm-values/
│       ├── agentgateway.yaml      # Helm values for kind
│       └── kagent.yaml            # Helm values for kind
├── scripts/
│   └── create-secrets.sh
├── .devcontainer/                 # GitHub Codespaces (kind + kubectl + helm)
└── Makefile
```

## Secrets

Not stored in git. API key is provided via `.env` or `GEMINI_API_KEY` env var:

```bash
# podman: writes podman/gemini-api-key.txt (mounted into container)
make podman-secrets

# kind / minipc: creates google-secret in agentgateway-system namespace
make kind-secrets
make minipc-secrets
```

## Testing

### agentgateway LLM API

```bash
# podman (port 3000)
curl http://localhost:3000/v1/chat/completions -X POST \
  -H "Content-Type: application/json" \
  -d '{"model":"gemini-2.0-flash-lite","messages":[{"role":"user","content":"Hello!"}]}'

# kind (port 8080)
curl http://localhost:8080/v1/chat/completions -X POST \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"Hello!"}]}'

# minipc (MetalLB IP)
curl http://192.168.0.253:8080/v1/chat/completions -X POST \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"Hello!"}]}'
```

### kagent A2A endpoint

The A2A endpoint streams responses as Server-Sent Events (SSE).

```bash
# kind (kagent UI on port 8081)
curl http://localhost:8081/a2a/kagent/k8s-agent -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "method": "message/stream",
    "params": {
      "message": {
        "role": "user",
        "parts": [{"kind": "text", "text": "How many nodes are in the cluster?"}]
      }
    },
    "id": "1"
  }'
```

The response is a stream of SSE events:

```
event: task_status_update
data: {"result": {"status": {"state": "submitted", ...}}}

event: task_status_update
data: {"result": {"status": {"state": "working", ...}}}

event: task_status_update          ← agent called a k8s tool, got data back
data: {"result": {"status": {"message": {"parts": [{"kind": "data", "data": {...}}]}}}}

event: task_status_update          ← final text answer
data: {"result": {"status": {"message": {"parts": [{"kind": "text", "text": "There are 2 nodes in the cluster."}]}}}}

event: task_artifact_update        ← final artifact (lastChunk: true marks the end)
data: {"result": {"artifact": {"parts": [{"kind": "text", "text": "..."}]}, "lastChunk": true}}
```

To extract just the final answer:

```bash
# kind
curl -s http://localhost:8081/a2a/kagent/k8s-agent -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"message/stream","params":{"message":{"role":"user","parts":[{"kind":"text","text":"List all namespaces"}]}},"id":"1"}' \
  | grep '"text":"[^"]*"' | tail -1

# minipc (port-forward svc/k8s-agent 8083:8080 -n kagent first)
curl -s http://localhost:8083/a2a/kagent/k8s-agent -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"message/stream","params":{"message":{"role":"user","parts":[{"kind":"text","text":"List all namespaces"}]}},"id":"1"}' \
  | grep '"text":"[^"]*"' | tail -1
```
