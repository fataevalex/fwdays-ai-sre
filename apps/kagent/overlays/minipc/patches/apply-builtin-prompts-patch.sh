#!/bin/bash
# The kagent chart renders kagent-builtin-prompts from its own templates with
# no values.yaml override hook, so this content is patched onto the live
# ConfigMap directly (excluded from ArgoCD drift detection via
# ignoreDifferences in kagent-app-patch.yaml). Re-run this after a chart
# version bump or a fresh cluster bootstrap, since a brand-new ConfigMap
# render won't carry this patch.
set -euo pipefail
cd "$(dirname "$0")"

kubectl patch configmap kagent-builtin-prompts -n kagent --type merge -p "$(python3 -c "
import json
with open('tool-usage-best-practices.txt') as f:
    content = f.read()
print(json.dumps({'data': {'tool-usage-best-practices': content}}))
")"
