SHELL := /bin/bash

.PHONY: up down logs ps restart test-card test-tools test-call

up:
	docker compose --env-file .env up --build -d

down:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps

restart:
	docker compose restart

test-card:
	curl -s http://localhost:8000/.well-known/agent.json | jq

test-tools:
	curl -s -X POST http://localhost:8000/task \
		-H "Content-Type: application/json" \
		-d '{"action":"list_tools"}' | jq

# Пример: make test-call TOOL=get_live_context
test-call:
	@if [ -z "$(TOOL)" ]; then echo "Usage: make test-call TOOL=<tool_name>"; exit 1; fi
	curl -s -X POST http://localhost:8000/task \
		-H "Content-Type: application/json" \
		-d "{\"action\":\"call_tool\",\"tool_name\":\"$(TOOL)\",\"arguments\":{}}" | jq