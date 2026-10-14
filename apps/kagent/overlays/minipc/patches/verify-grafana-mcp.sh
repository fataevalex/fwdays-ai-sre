#!/bin/bash
# Quick health check for the kagent-grafana-mcp tool server: confirms the
# pod is up, the RemoteMCPServer resource is Accepted, and an actual
# list_datasources call succeeds end-to-end (connectivity + auth + URL path
# all correct). Run after touching anything in apps/kagent — this is the
# fastest way to confirm reapply-live-patches.sh actually fixed things.
set -euo pipefail

echo "--- pod ---"
kubectl get pods -n kagent -l app.kubernetes.io/name=grafana-mcp 2>/dev/null \
  || kubectl get pods -n kagent | grep grafana-mcp

echo "--- RemoteMCPServer status ---"
kubectl get remotemcpserver kagent-grafana-mcp -n kagent \
  -o jsonpath='{.status.conditions}' | python3 -m json.tool

echo "--- live list_datasources call ---"
kubectl run grafana-mcp-verify --rm -i --restart=Never --image=curlimages/curl -n kagent -- sh -c '
curl -s -X POST http://kagent-grafana-mcp.kagent:8000/mcp \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"verify\",\"version\":\"1\"}}}" \
  -D /tmp/h -o /tmp/b
SID=$(grep -i Mcp-Session-Id /tmp/h | tr -d "\r" | cut -d" " -f2)
curl -s -X POST http://kagent-grafana-mcp.kagent:8000/mcp \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SID" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"list_datasources\",\"arguments\":{}}}"
echo
'
