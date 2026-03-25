# fwdays-ai-sre

Lab-1: Basic Agentic Infrastructure deployment of [kagent](https://kagent.dev), [agentgateway](https://agentgateway.dev), [Phoenix](https://phoenix.arize.com) and [Qdrant](https://qdrant.tech).

| Environment | Tool | How |
|---|---|---|
| **podman** (local laptop) | podman compose | standalone agentgateway binary + kagent containers + Phoenix + Qdrant |
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
| Phoenix UI | http://localhost:6006 |
| Qdrant REST API | http://localhost:6333 |

```bash
make podman-test-agentgateway  # test LLM routing
make podman-down               # stop
```

### kind (local dev / GitHub Codespaces)

```bash
cp .env.example .env
# edit .env → set GEMINI_API_KEY

# GitHub Codespaces: kind and helm are installed automatically via devcontainer post-create
# On a plain Linux machine (e.g. CI runner) install tools first:
make tools-install

make dev-up
```

| Service | URL |
|---|---|
| kagent UI | http://localhost:8081 (NodePort 30081) |
| agentgateway | http://localhost:8080 (NodePort 30080) |
| Phoenix UI | `make kind-port-forward-phoenix` → http://localhost:6006 |
| Qdrant REST API | `make kind-port-forward-qdrant` → http://localhost:6333 |

```bash
make kind-port-forward-kagent        # or use NodePort directly
make kind-port-forward-agentgateway
make kind-port-forward-phoenix
make kind-port-forward-qdrant
make dev-down                        # tear down
```

### minipc homelab (ArgoCD)

```bash
make minipc-secrets                  # create google-secret from .env
make minipc-agentgateway-admin-secret  # create oauth2-proxy secret for agentgateway admin
make minipc-kagent-secret            # create oauth2-proxy secret for kagent
make minipc-phoenix-secret           # create oauth2-proxy secret for Phoenix
make minipc-install                  # kubectl apply argocd/app-of-apps-minipc.yaml
make minipc-status                   # watch ArgoCD sync
```

> For `minipc-phoenix-secret` you need to create a `phoenix` OIDC client in Keycloak first:
> Realm `homelab` → Clients → Create → Client ID: `phoenix`, redirect URI: `https://phoenix.local/oauth2/callback`

| Service | URL | Auth |
|---|---|---|
| agentgateway LLM API | http://192.168.0.253:8080/v1 | — |
| agentgateway Admin UI | https://agentgateway.local | Keycloak |
| kagent UI | https://kagent.local | Keycloak |
| Phoenix UI | https://phoenix.local | Keycloak |
| Qdrant REST API | ClusterIP only — port-forward to access | — |

```bash
# agentgateway Admin UI
kubectl port-forward -n agentgateway-system \
  $(kubectl get pod -n agentgateway-system -l app.kubernetes.io/name=agentgateway-proxy -o name | head -1) \
  15000:15000
# → http://localhost:15000/ui/

# kagent A2A endpoint
kubectl port-forward svc/k8s-agent 8083:8080 -n kagent

# Qdrant REST API
kubectl port-forward svc/qdrant 6333:6333 -n qdrant
# → http://localhost:6333
```

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
make podman-test-agentgateway      # test LLM API

# kind (no ArgoCD)
make tools-install                 # install kind + helm (needed on plain Linux / CI)
make dev-up                        # full setup: kind + secrets + helm install
make dev-down                      # tear down
make dev-reset                     # dev-down + dev-up
make kind-up / kind-down           # manage kind cluster
make kind-secrets                  # create Gemini secret
make kind-install                  # helm install everything
make kind-install-agentgateway     # helm install agentgateway only
make kind-install-kagent           # helm install kagent only
make kind-install-phoenix          # helm install Phoenix only
make kind-install-qdrant           # helm install Qdrant only
make kind-uninstall                # helm uninstall everything
make kind-pods                     # show pods
make kind-port-forward-kagent      # port-forward kagent → :8081
make kind-port-forward-agentgateway  # port-forward agentgateway → :8080
make kind-port-forward-phoenix     # port-forward Phoenix UI → :6006
make kind-port-forward-qdrant      # port-forward Qdrant REST API → :6333

# minipc (ArgoCD)
make minipc-secrets                # create Gemini secret
make minipc-agentgateway-admin-secret  # create oauth2-proxy secret for agentgateway admin
make minipc-kagent-secret          # create oauth2-proxy secret for kagent
make minipc-phoenix-secret         # create oauth2-proxy secret for Phoenix
make minipc-install                # deploy via ArgoCD app-of-apps
make minipc-uninstall              # remove apps
make minipc-sync                   # force sync fwdays-ai-sre-minipc app
make minipc-status                 # ArgoCD app status
make minipc-pods                   # show pods in all namespaces

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
│   │       ├── minipc/        # nodeSelector + oauth2-proxy + Traefik IngressRoute
│   │       └── kind/          # Gateway resources (no ArgoCD, no auth)
│   ├── kagent/
│   │   ├── base/              # ArgoCD Applications + nginx ConfigMap
│   │   │   └── kustomize-patch/   # wave-3 Deployment patch for nginx mount
│   │   └── overlays/
│   │       ├── minipc/        # nodeSelector + oauth2-proxy + Traefik IngressRoute
│   │       └── kind/          # nginx ConfigMap + deployment patch
│   ├── phoenix/
│   │   ├── base/              # ArgoCD Applications (Helm from GitHub)
│   │   └── overlays/
│   │       ├── minipc/        # nodeSelector + oauth2-proxy + Traefik IngressRoute
│   │       └── kind/          # (placeholder)
│   └── qdrant/
│       ├── base/              # ArgoCD Application (qdrant/qdrant Helm chart)
│       └── overlays/
│           ├── minipc/        # nodeSelector, ClusterIP only
│           └── kind/          # (placeholder)
├── argocd/
│   └── app-of-apps-minipc.yaml    # minipc entry point
├── environments/
│   └── minipc/                    # kustomize entry point (all apps + helm repos)
├── podman/
│   ├── compose.yaml               # agentgateway + Phoenix + Qdrant
│   └── config.yaml                # standalone agentgateway config
├── kind/
│   ├── cluster.yaml               # kind cluster config
│   └── helm-values/
│       ├── agentgateway.yaml
│       ├── kagent.yaml
│       ├── phoenix.yaml
│       └── qdrant.yaml
├── scripts/
│   └── create-secrets.sh
├── .devcontainer/                 # GitHub Codespaces (kind + kubectl + helm)
└── Makefile
```

## Components

| Component | Version | Purpose |
|---|---|---|
| agentgateway | v2.2.1 | OpenAI-compatible LLM gateway (Ollama + Gemini) |
| kagent | 0.8.0-beta6 | Kubernetes AI agent |
| Phoenix | chart 5.0.18 / app 13.18.2 | LLM observability & tracing (OpenTelemetry) |
| Qdrant | 1.17.0 | Vector database |

## Secrets

Not stored in git. Created via Makefile targets or manually:

```bash
# Gemini API key → google-secret in agentgateway-system
make kind-secrets       # kind
make minipc-secrets     # minipc

# OAuth2-proxy secrets (minipc only, Keycloak OIDC)
make minipc-agentgateway-admin-secret  # needs AGENTGATEWAY_ADMIN_CLIENT_SECRET in .env
make minipc-kagent-secret              # needs KAGENT_CLIENT_SECRET in .env
make minipc-phoenix-secret             # needs PHOENIX_CLIENT_SECRET in .env
```

`.env` variables (see `.env.example`):

```
GEMINI_API_KEY=...
OLLAMA_HOST=192.168.0.152
OLLAMA_PORT=11434
AGENTGATEWAY_ADMIN_CLIENT_SECRET=...
KAGENT_CLIENT_SECRET=...
PHOENIX_CLIENT_SECRET=...
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

### Qdrant

```bash
# health check (after port-forward to :6333)
curl http://localhost:6333/healthz

# list collections
curl http://localhost:6333/collections
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
        "messageId": "msg-1",
        "parts": [{"kind": "text", "text": "How many nodes are in the cluster?"}]
      }
    },
    "id": "1"
  }'

# minipc (port-forward svc/k8s-agent 18083:8080 -n kagent first)
curl http://localhost:18083 -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "method": "message/stream",
    "params": {
      "message": {
        "role": "user",
        "messageId": "msg-1",
        "parts": [{"kind": "text", "text": "List all pods in all namespaces"}]
      }
    },
    "id": "1"
  }'
```
