#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Create Tool
# Usage:
#   ./create-tool.sh <api-key> <agent-id> datastore <datastore-id>
#   ./create-tool.sh <api-key> <agent-id> http     '<json-config>'
#   ./create-tool.sh <api-key> <agent-id> form     <form-id>

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <type> <config-or-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <type> <config-or-id>}"
TOOL_TYPE="${3:?Usage: $0 <api-key> <agent-id> <type> <config-or-id>}"
CONFIG_OR_ID="${4:?Usage: $0 <api-key> <agent-id> <type> <config-or-id>}"
BASE_URL="https://api.chatvolt.ai"

case "$TOOL_TYPE" in
  datastore)
    echo "Creating datastore tool: ${CONFIG_OR_ID}" >&2
    BODY=$(python3 -c "
import json
print(json.dumps({
    'type': 'datastore',
    'datastoreId': '${CONFIG_OR_ID}'
}))
")
    ;;

  form)
    echo "Creating form tool: ${CONFIG_OR_ID}" >&2
    BODY=$(python3 -c "
import json
print(json.dumps({
    'type': 'form',
    'formId': '${CONFIG_OR_ID}'
}))
")
    ;;

  http)
    echo "Creating HTTP tool..." >&2
    # Validate that CONFIG_OR_ID is valid JSON
    if ! echo "$CONFIG_OR_ID" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
      echo "ERROR: HTTP tool config must be valid JSON" >&2
      echo "Usage: $0 <api-key> <agent-id> http '{\"config\": {...}}'" >&2
      exit 1
    fi
    BODY="$CONFIG_OR_ID"
    ;;

  *)
    echo "ERROR: Unknown tool type '$TOOL_TYPE'. Use: datastore, http, or form" >&2
    exit 1
    ;;
esac

RESPONSE=$(curl -s -X POST "${BASE_URL}/api/agents/${AGENT_ID}/tools" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

echo "$RESPONSE" | python3 -c "
import json, sys

data = json.load(sys.stdin)

# Handle error responses
if isinstance(data, dict) and ('error' in data or 'message' in data):
    err = data.get('error') or data.get('message') or str(data)
    print(f'ERROR: {err}')
    sys.exit(1)

tool_id = ''
if isinstance(data, dict):
    tool_id = data.get('id', data.get('toolId', ''))
elif isinstance(data, str):
    tool_id = data

print('✅ Tool criada com sucesso!')
if tool_id:
    print(f'   Tool ID: {tool_id}')
print()
print(json.dumps(data, indent=2, ensure_ascii=False))
" 2>&1
