#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Update Tool
# Usage: ./update-tool.sh <api-key> <agent-id> <tool-id> '<json-config>'

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <tool-id> <json-config>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <tool-id> <json-config>}"
TOOL_ID="${3:?Usage: $0 <api-key> <agent-id> <tool-id> <json-config>}"
NEW_CONFIG="${4:?Usage: $0 <api-key> <agent-id> <tool-id> <json-config>}"
BASE_URL="https://api.chatvolt.ai"

echo "Updating tool: ${TOOL_ID}" >&2

# Validate JSON
if ! echo "$NEW_CONFIG" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  echo "ERROR: Config must be valid JSON" >&2
  exit 1
fi

RESPONSE=$(curl -s -X PATCH "${BASE_URL}/api/agents/${AGENT_ID}/tools/${TOOL_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$NEW_CONFIG")

echo "$RESPONSE" | python3 -c "
import json, sys

data = json.load(sys.stdin)

# Handle error responses
if isinstance(data, dict) and ('error' in data or 'message' in data):
    err = data.get('error') or data.get('message') or str(data)
    print(f'ERROR: {err}')
    sys.exit(1)

print('✅ Tool atualizada com sucesso!')
print()
print(json.dumps(data, indent=2, ensure_ascii=False))
" 2>&1
