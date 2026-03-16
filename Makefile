SHELL := /bin/bash
.DEFAULT_GOAL := help

# ── Configuration ─────────────────────────────────────────────────────────────
KUBECONFIG              ?= ~/.kube/minipc-k3s.yaml
KIND_VERSION            ?= v0.27.0
KIND_CLUSTER            ?= fwdays-ai-sre
KIND_KUBECONFIG         ?= kubeconfig-kind.yaml
ARGOCD_NAMESPACE        ?= argocd
ARGOCD_SERVER           ?= localhost:8080
ARGOCD_USER             ?= admin

AGENTGATEWAY_VERSION        ?= v2.2.1
AGENTGATEWAY_STANDALONE_VER ?= v1.0.0-rc.2
KAGENT_VERSION              ?= 0.8.0-beta6

PODMAN                  ?= podman
# On macOS with podman machine, docker-compose uses docker.sock → podman-machine-default.
# Use DOCKER_HOST to redirect to the active machine socket if needed.
# Default: let podman resolve via its default connection.
PODMAN_COMPOSE          ?= podman compose

# ── Tools install ─────────────────────────────────────────────────────────────

.PHONY: tools-install
tools-install: ## Install kind + helm (kubectl assumed present)
	@echo "==> Installing kind $(KIND_VERSION)..."
	@OS=$$(uname -s | tr '[:upper:]' '[:lower:]'); \
	ARCH=$$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'); \
	DEST=$$(if [ -w /usr/local/bin ]; then echo /usr/local/bin; else echo $$HOME/.local/bin; fi); \
	mkdir -p "$${DEST}"; \
	curl -sLo "$${DEST}/kind" \
	  "https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-$${OS}-$${ARCH}" && \
	chmod +x "$${DEST}/kind" && \
	echo "==> kind installed to $${DEST}/kind"
	@echo "==> Installing Helm..."
	@HELM_DEST=$$(if [ -w /usr/local/bin ]; then echo /usr/local/bin; else echo $$HOME/.local/bin; fi); \
	mkdir -p "$${HELM_DEST}"; \
	curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | \
	  VERIFY_CHECKSUM=false HELM_INSTALL_DIR="$${HELM_DEST}" USE_SUDO=false bash
	@echo "==> Versions:"
	@kind version
	@helm version --short

# ── Help ──────────────────────────────────────────────────────────────────────
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2}' | sort

# ══════════════════════════════════════════════════════════════════════════════
# MINIPC — deploy via ArgoCD (ArgoCD is pre-installed in the cluster)
# ══════════════════════════════════════════════════════════════════════════════

.PHONY: minipc-secrets
minipc-secrets: ## [minipc] Create Gemini API secret (reads .env or GEMINI_API_KEY)
	KUBECONFIG=$(KUBECONFIG) ./scripts/create-secrets.sh

.PHONY: minipc-install
minipc-install: ## [minipc] Deploy via ArgoCD app-of-apps
	kubectl --kubeconfig $(KUBECONFIG) apply -f argocd/app-of-apps-minipc.yaml
	@echo "==> Watching sync status (Ctrl+C to stop)..."
	@kubectl --kubeconfig $(KUBECONFIG) get applications -n $(ARGOCD_NAMESPACE) -w

.PHONY: minipc-uninstall
minipc-uninstall: ## [minipc] Remove all apps (ArgoCD cascade delete)
	kubectl --kubeconfig $(KUBECONFIG) delete -f argocd/app-of-apps-minipc.yaml --ignore-not-found

.PHONY: minipc-sync
minipc-sync: ## [minipc] Force sync fwdays-ai-sre-minipc app in ArgoCD
	argocd app sync fwdays-ai-sre-minipc \
	  --server $(ARGOCD_SERVER) --insecure
	argocd app wait fwdays-ai-sre-minipc \
	  --server $(ARGOCD_SERVER) --insecure --health

.PHONY: minipc-status
minipc-status: ## [minipc] Show ArgoCD application status
	kubectl --kubeconfig $(KUBECONFIG) get applications -n $(ARGOCD_NAMESPACE)

.PHONY: minipc-pods
minipc-pods: ## [minipc] Show pods for deployed apps
	kubectl --kubeconfig $(KUBECONFIG) get pods -n kagent
	kubectl --kubeconfig $(KUBECONFIG) get pods -n agentgateway-system

.PHONY: minipc-logs-kagent
minipc-logs-kagent: ## [minipc] Tail kagent controller logs
	kubectl --kubeconfig $(KUBECONFIG) logs -n kagent deploy/kagent-controller -f

.PHONY: minipc-logs-agentgateway
minipc-logs-agentgateway: ## [minipc] Tail agentgateway controller logs
	kubectl --kubeconfig $(KUBECONFIG) logs -n agentgateway-system deploy/agentgateway -f

# ══════════════════════════════════════════════════════════════════════════════
# KIND — deploy directly via Helm (no ArgoCD)
# ══════════════════════════════════════════════════════════════════════════════

.PHONY: kind-up
kind-up: ## [kind] Create kind cluster
	kind create cluster --config kind/cluster.yaml --kubeconfig $(KIND_KUBECONFIG)
	@echo "==> Kubeconfig: $(KIND_KUBECONFIG)"

.PHONY: kind-down
kind-down: ## [kind] Delete kind cluster
	kind delete cluster --name $(KIND_CLUSTER)
	rm -f $(KIND_KUBECONFIG)

.PHONY: kind-secrets
kind-secrets: ## [kind] Create Gemini API secret (reads .env or GEMINI_API_KEY)
	KUBECONFIG=$(KIND_KUBECONFIG) ./scripts/create-secrets.sh

.PHONY: kind-gateway-api-crds
kind-gateway-api-crds: ## [kind] Install Kubernetes Gateway API CRDs (required by agentgateway)
	kubectl --kubeconfig $(KIND_KUBECONFIG) apply -f \
	  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

.PHONY: kind-install-agentgateway
kind-install-agentgateway: kind-gateway-api-crds ## [kind] Install agentgateway via Helm
	HELM_EXPERIMENTAL_OCI=1 helm upgrade --install agentgateway-crds \
	  oci://ghcr.io/kgateway-dev/charts/agentgateway-crds \
	  --version $(AGENTGATEWAY_VERSION) \
	  --namespace agentgateway-system --create-namespace \
	  --kubeconfig $(KIND_KUBECONFIG) \
	  --wait
	HELM_EXPERIMENTAL_OCI=1 helm upgrade --install agentgateway \
	  oci://ghcr.io/kgateway-dev/charts/agentgateway \
	  --version $(AGENTGATEWAY_VERSION) \
	  --namespace agentgateway-system \
	  --values kind/helm-values/agentgateway.yaml \
	  --kubeconfig $(KIND_KUBECONFIG) \
	  --wait
	kubectl --kubeconfig $(KIND_KUBECONFIG) apply \
	  -k apps/agentgateway/overlays/kind

.PHONY: kind-install-kagent
kind-install-kagent: ## [kind] Install kagent via Helm
	HELM_EXPERIMENTAL_OCI=1 helm upgrade --install kagent-crds \
	  oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
	  --version $(KAGENT_VERSION) \
	  --namespace kagent --create-namespace \
	  --kubeconfig $(KIND_KUBECONFIG) \
	  --wait
	HELM_EXPERIMENTAL_OCI=1 helm upgrade --install kagent \
	  oci://ghcr.io/kagent-dev/kagent/helm/kagent \
	  --version $(KAGENT_VERSION) \
	  --namespace kagent \
	  --values kind/helm-values/kagent.yaml \
	  --kubeconfig $(KIND_KUBECONFIG) \
	  --wait
	kubectl --kubeconfig $(KIND_KUBECONFIG) apply \
	  -k apps/kagent/overlays/kind

.PHONY: kind-install
kind-install: kind-install-agentgateway kind-install-kagent ## [kind] Install all apps via Helm

.PHONY: kind-uninstall
kind-uninstall: ## [kind] Uninstall all apps
	helm uninstall kagent -n kagent --kubeconfig $(KIND_KUBECONFIG) --ignore-not-found
	helm uninstall kagent-crds -n kagent --kubeconfig $(KIND_KUBECONFIG) --ignore-not-found
	helm uninstall agentgateway -n agentgateway-system --kubeconfig $(KIND_KUBECONFIG) --ignore-not-found
	helm uninstall agentgateway-crds -n agentgateway-system --kubeconfig $(KIND_KUBECONFIG) --ignore-not-found

.PHONY: kind-pods
kind-pods: ## [kind] Show pods for deployed apps
	kubectl --kubeconfig $(KIND_KUBECONFIG) get pods -n kagent
	kubectl --kubeconfig $(KIND_KUBECONFIG) get pods -n agentgateway-system

.PHONY: kind-logs-kagent
kind-logs-kagent: ## [kind] Tail kagent controller logs
	kubectl --kubeconfig $(KIND_KUBECONFIG) logs -n kagent deploy/kagent-controller -f

.PHONY: kind-logs-agentgateway
kind-logs-agentgateway: ## [kind] Tail agentgateway controller logs
	kubectl --kubeconfig $(KIND_KUBECONFIG) logs -n agentgateway-system deploy/agentgateway -f

.PHONY: kind-port-forward-kagent
kind-port-forward-kagent: ## [kind] Port-forward kagent UI → localhost:8081
	kubectl --kubeconfig $(KIND_KUBECONFIG) port-forward svc/kagent-ui \
	  -n kagent 8081:8080

.PHONY: kind-port-forward-agentgateway
kind-port-forward-agentgateway: ## [kind] Port-forward agentgateway → localhost:8080
	kubectl --kubeconfig $(KIND_KUBECONFIG) port-forward svc/agentgateway-proxy \
	  -n agentgateway-system 8080:80

# ── Full dev workflow ─────────────────────────────────────────────────────────

.PHONY: dev-up
dev-up: kind-up kind-secrets kind-install ## [kind] Full dev setup: kind cluster + secrets + helm install
	@bash .devcontainer/start-port-forwards.sh || true
	@echo ""
	@echo "==> Dev environment ready!"
	@echo "    kagent UI:      http://localhost:8081"
	@echo "    agentgateway:  http://localhost:8080"

.PHONY: dev-down
dev-down: kind-uninstall kind-down ## [kind] Tear down dev environment

.PHONY: dev-reset
dev-reset: dev-down dev-up ## [kind] Reset dev environment from scratch

# ══════════════════════════════════════════════════════════════════════════════
# PODMAN — standalone agentgateway + kagent via podman compose (local laptop)
# ══════════════════════════════════════════════════════════════════════════════

.PHONY: podman-secrets
podman-secrets: ## [podman] Write Gemini API key to podman/gemini-api-key.txt (reads .env or GEMINI_API_KEY)
	@if [ -f .env ]; then set -a && source .env && set +a; fi; \
	if [ -z "$${GEMINI_API_KEY:-}" ]; then \
	  echo "ERROR: set GEMINI_API_KEY in .env or environment"; exit 1; \
	fi; \
	echo -n "Bearer $${GEMINI_API_KEY}" > podman/gemini-api-key.txt
	@echo "==> podman/gemini-api-key.txt written"

.PHONY: podman-pull
podman-pull: ## [podman] Pull agentgateway image
	$(PODMAN) pull cr.agentgateway.dev/agentgateway:$(AGENTGATEWAY_STANDALONE_VER)

.PHONY: podman-up
podman-up: podman-secrets ## [podman] Start agentgateway (standalone, no k8s needed)
	$(PODMAN_COMPOSE) -f podman/compose.yaml up -d --remove-orphans
	@echo ""
	@echo "==> agentgateway started:"
	@echo "    LLM API  (OpenAI-compatible): http://localhost:3000/v1"
	@echo "    Admin UI:                     http://localhost:15000/ui/"
	@echo ""
	@echo "==> For full kagent deployment use: make dev-up (kind + Helm)"

.PHONY: podman-down
podman-down: ## [podman] Stop all services
	$(PODMAN_COMPOSE) -f podman/compose.yaml down

.PHONY: podman-logs
podman-logs: ## [podman] Tail logs from all services
	$(PODMAN_COMPOSE) -f podman/compose.yaml logs -f

.PHONY: podman-logs-agentgateway
podman-logs-agentgateway: ## [podman] Tail agentgateway logs
	$(PODMAN) logs -f agentgateway


.PHONY: podman-status
podman-status: ## [podman] Show running containers
	$(PODMAN_COMPOSE) -f podman/compose.yaml ps

.PHONY: podman-test-agentgateway
podman-test-agentgateway: ## [podman] Test agentgateway LLM routing
	curl -s http://localhost:3000/v1/chat/completions -X POST \
	  -H "Content-Type: application/json" \
	  -d '{"model":"gemini-2.0-flash-lite","messages":[{"role":"user","content":"Say hello in one sentence."}]}' \
	  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"


# ── Validation ────────────────────────────────────────────────────────────────

.PHONY: validate
validate: validate-minipc validate-kind ## Validate all kustomize overlays

.PHONY: validate-minipc
validate-minipc: ## Validate minipc overlay
	kubectl kustomize environments/minipc

.PHONY: validate-kind
validate-kind: ## Validate kind overlay
	kubectl kustomize apps/agentgateway/overlays/kind
	kubectl kustomize apps/kagent/overlays/kind

# ── Tests ─────────────────────────────────────────────────────────────────────

.PHONY: test-kagent
test-kagent: ## Test kagent k8s-agent (set KAGENT_HOST for non-default endpoint)
	@HOST=$${KAGENT_HOST:-https://kagent.local}; \
	curl -s "$${HOST}/a2a/kagent/k8s-agent" -X POST \
	  -H "Content-Type: application/json" \
	  -H "Accept: text/event-stream" \
	  -d '{"jsonrpc":"2.0","method":"message/stream","params":{"message":{"role":"user","parts":[{"kind":"text","text":"How many nodes are in the cluster?"}]}},"id":"test-1"}' \
	  | grep -o '"text":"[^"]*"' | tail -1

.PHONY: test-agentgateway
test-agentgateway: ## Test agentgateway LLM routing (set AGENTGATEWAY_HOST for non-default)
	@HOST=$${AGENTGATEWAY_HOST:-http://agentgateway.local}; \
	curl -s "$${HOST}/v1/chat/completions" -X POST \
	  -H "Content-Type: application/json" \
	  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"Say hello in one sentence."}]}' \
	  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
