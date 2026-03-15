SHELL := /bin/bash
.DEFAULT_GOAL := help

KUBECONFIG         ?= ~/.kube/minipc-k3s.yaml
KIND_CLUSTER       ?= fwdays-ai-sre
KIND_KUBECONFIG    ?= kubeconfig-kind.yaml
ARGOCD_NAMESPACE   ?= argocd
ARGOCD_SERVER      ?= localhost:8082
ARGOCD_USER        ?= admin

# ── Helpers ───────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}' | sort

# ── Kind cluster ──────────────────────────────────────────────────────────────

.PHONY: kind-up
kind-up: ## Create kind cluster
	kind create cluster --config kind/cluster.yaml --kubeconfig $(KIND_KUBECONFIG)
	@echo "==> Kubeconfig written to $(KIND_KUBECONFIG)"

.PHONY: kind-down
kind-down: ## Delete kind cluster
	kind delete cluster --name $(KIND_CLUSTER)
	rm -f $(KIND_KUBECONFIG)

.PHONY: kind-kubeconfig
kind-kubeconfig: ## Export kubeconfig for kind cluster
	kind export kubeconfig --name $(KIND_CLUSTER) --kubeconfig $(KIND_KUBECONFIG)

# ── Bootstrap (run once per cluster) ─────────────────────────────────────────

.PHONY: bootstrap-argocd-kind
bootstrap-argocd-kind: ## Install ArgoCD into kind cluster
	KUBECONFIG=$(KIND_KUBECONFIG) ./scripts/bootstrap-argocd-kind.sh

.PHONY: bootstrap-argocd-repos
bootstrap-argocd-repos: ## Register OCI Helm repos with ArgoCD
	ARGOCD_SERVER=$(ARGOCD_SERVER) ARGOCD_USER=$(ARGOCD_USER) \
	ARGOCD_PASSWORD=$(ARGOCD_PASSWORD) ./scripts/bootstrap-argocd-repos.sh

.PHONY: bootstrap-secrets
bootstrap-secrets: ## Create Gemini API key secret (reads .env or GEMINI_API_KEY env var)
	KUBECONFIG=$(KUBECONFIG) ./scripts/create-secrets.sh

.PHONY: bootstrap-secrets-kind
bootstrap-secrets-kind: ## Create Gemini API key secret in kind cluster
	KUBECONFIG=$(KIND_KUBECONFIG) ./scripts/create-secrets.sh

# ── Deploy via ArgoCD app-of-apps ─────────────────────────────────────────────

.PHONY: install-minipc
install-minipc: ## Deploy to minipc cluster via ArgoCD app-of-apps
	kubectl --kubeconfig $(KUBECONFIG) apply -f argocd/app-of-apps-minipc.yaml
	@echo "==> App-of-apps applied. Watch: make status KUBECONFIG=$(KUBECONFIG)"

.PHONY: install-kind
install-kind: ## Deploy to kind cluster via ArgoCD app-of-apps
	kubectl --kubeconfig $(KIND_KUBECONFIG) apply -f argocd/app-of-apps-kind.yaml
	@echo "==> App-of-apps applied. Watch: make status KUBECONFIG=$(KIND_KUBECONFIG)"

.PHONY: uninstall-minipc
uninstall-minipc: ## Remove all apps from minipc (ArgoCD cascade delete)
	kubectl --kubeconfig $(KUBECONFIG) delete -f argocd/app-of-apps-minipc.yaml --ignore-not-found

.PHONY: uninstall-kind
uninstall-kind: ## Remove all apps from kind cluster
	kubectl --kubeconfig $(KIND_KUBECONFIG) delete -f argocd/app-of-apps-kind.yaml --ignore-not-found

# ── Individual app sync ───────────────────────────────────────────────────────

.PHONY: sync-agentgateway
sync-agentgateway: ## Force sync agentgateway apps
	argocd app sync agentgateway-crds agentgateway --server $(ARGOCD_SERVER) --insecure
	argocd app wait agentgateway --server $(ARGOCD_SERVER) --insecure --health

.PHONY: sync-kagent
sync-kagent: ## Force sync kagent apps
	argocd app sync kagent-crds kagent kagent-nginx-patch --server $(ARGOCD_SERVER) --insecure
	argocd app wait kagent --server $(ARGOCD_SERVER) --insecure --health

.PHONY: sync-all
sync-all: ## Force sync all apps
	argocd app sync -l app.kubernetes.io/part-of=fwdays-ai-sre \
	  --server $(ARGOCD_SERVER) --insecure || \
	argocd app sync fwdays-ai-sre-minipc --server $(ARGOCD_SERVER) --insecure

# ── Full dev workflow ─────────────────────────────────────────────────────────

.PHONY: dev-up
dev-up: kind-up bootstrap-argocd-kind bootstrap-secrets-kind install-kind ## Full local dev setup: kind + ArgoCD + secrets + deploy (note: ArgoCD on minipc is pre-installed)
	@echo "==> Dev environment ready!"
	@echo "    kagent UI:       http://localhost:8081"
	@echo "    agentgateway:   http://localhost:8080"
	@echo "    ArgoCD UI:      http://localhost:8082  (run: make port-forward-argocd)"

.PHONY: dev-down
dev-down: uninstall-kind kind-down ## Tear down dev environment

.PHONY: dev-reset
dev-reset: dev-down dev-up ## Reset dev environment from scratch

# ── Port forwarding (kind) ────────────────────────────────────────────────────

.PHONY: port-forward-argocd
port-forward-argocd: ## Port-forward ArgoCD UI (kind) → localhost:8082
	kubectl --kubeconfig $(KIND_KUBECONFIG) port-forward svc/argocd-server \
	  -n $(ARGOCD_NAMESPACE) 8082:443

.PHONY: port-forward-kagent
port-forward-kagent: ## Port-forward kagent UI (kind) → localhost:8081
	kubectl --kubeconfig $(KIND_KUBECONFIG) port-forward svc/kagent-ui \
	  -n kagent 8081:80

.PHONY: port-forward-agentgateway
port-forward-agentgateway: ## Port-forward agentgateway (kind) → localhost:8080
	kubectl --kubeconfig $(KIND_KUBECONFIG) port-forward svc/agentgateway-proxy \
	  -n agentgateway-system 8080:80

# ── Status & logs ─────────────────────────────────────────────────────────────

.PHONY: status
status: ## Show ArgoCD app status
	kubectl --kubeconfig $(KUBECONFIG) get applications -n $(ARGOCD_NAMESPACE)

.PHONY: pods
pods: ## Show all pods for deployed apps
	kubectl --kubeconfig $(KUBECONFIG) get pods -n kagent -n agentgateway-system 2>/dev/null; \
	kubectl --kubeconfig $(KUBECONFIG) get pods -n kagent; \
	kubectl --kubeconfig $(KUBECONFIG) get pods -n agentgateway-system

.PHONY: logs-kagent
logs-kagent: ## Tail kagent controller logs
	kubectl --kubeconfig $(KUBECONFIG) logs -n kagent deploy/kagent-controller -f

.PHONY: logs-agentgateway
logs-agentgateway: ## Tail agentgateway controller logs
	kubectl --kubeconfig $(KUBECONFIG) logs -n agentgateway-system deploy/agentgateway -f

# ── Validation ────────────────────────────────────────────────────────────────

.PHONY: validate
validate: validate-minipc validate-kind ## Validate all kustomize overlays

.PHONY: validate-minipc
validate-minipc: ## Validate minipc overlay
	kubectl kustomize environments/minipc

.PHONY: validate-kind
validate-kind: ## Validate kind overlay
	kubectl kustomize environments/kind

# ── Test ──────────────────────────────────────────────────────────────────────

.PHONY: test-kagent
test-kagent: ## Send a test query to kagent k8s-agent
	@HOST=$${KAGENT_HOST:-https://kagent.local}; \
	curl -s "$${HOST}/a2a/kagent/k8s-agent" -X POST \
	  -H "Content-Type: application/json" \
	  -H "Accept: text/event-stream" \
	  -d '{"jsonrpc":"2.0","method":"message/stream","params":{"message":{"role":"user","parts":[{"kind":"text","text":"How many nodes are in the cluster?"}]}},"id":"test-1"}' \
	  | grep -o '"text":"[^"]*"' | head -5

.PHONY: test-agentgateway
test-agentgateway: ## Send a test LLM request to agentgateway
	@HOST=$${AGENTGATEWAY_HOST:-http://agentgateway.local}; \
	curl -s "$${HOST}/v1/chat/completions" -X POST \
	  -H "Content-Type: application/json" \
	  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"Say hello in one sentence."}]}' \
	  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])"
