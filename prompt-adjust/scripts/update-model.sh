#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Update Model
# Usage: ./update-model.sh <api-key> <agent-id> <model-name>

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <model-name>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <model-name>}"
MODEL="${3:?Usage: $0 <api-key> <agent-id> <model-name>}"
BASE_URL="https://api.chatvolt.ai"

echo "Updating model to '${MODEL}' for agent: ${AGENT_ID}" >&2

RESULT=$(curl -s -X PATCH "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'modelName': '${MODEL}'}))")")

echo "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
err = data.get('error') or data.get('message')
if err:
    print(f'ERROR: {err}')
    sys.exit(1)
old = data.get('modelName', '?')
print(f'✅ Modelo atualizado com sucesso!')
print(f'   Modelo: {old}')
print(f'   Timestamp: {data.get(\"updatedAt\", \"?\")}')
" 2>&1
