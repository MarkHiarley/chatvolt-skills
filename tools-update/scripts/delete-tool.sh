#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Delete Tool
# Usage: ./delete-tool.sh <api-key> <agent-id> <tool-id>

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <tool-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <tool-id>}"
TOOL_ID="${3:?Usage: $0 <api-key> <agent-id> <tool-id>}"
BASE_URL="https://api.chatvolt.ai"

# First, get tool info for confirmation
echo "Fetching tool info for confirmation..." >&2
TOOL_INFO=$(curl -s "${BASE_URL}/api/agents/${AGENT_ID}/tools/${TOOL_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json")

TOOL_NAME=$(echo "$TOOL_INFO" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, dict):
    config = data.get('config', {})
    name = config.get('name') or data.get('type', 'unknown')
    print(name)
" 2>/dev/null || echo "unknown")

echo ""
echo "You are about to delete tool:"
echo "  ID:   ${TOOL_ID}"
echo "  Name: ${TOOL_NAME}"
echo ""

read -r -p "Are you sure? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" && "$CONFIRM" != "yes" ]]; then
  echo "Cancelled."
  exit 0
fi

echo "Deleting tool: ${TOOL_ID}" >&2

RESPONSE=$(curl -s -X DELETE "${BASE_URL}/api/agents/${AGENT_ID}/tools/${TOOL_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json")

# Check if response is empty (success) or has error
if [ -z "$RESPONSE" ]; then
  echo "✅ Tool deletada com sucesso!"
else
  echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, dict) and ('error' in data or 'message' in data):
    err = data.get('error') or data.get('message') or str(data)
    print(f'ERROR: {err}')
    sys.exit(1)
print('✅ Tool deletada com sucesso!')
print(json.dumps(data, indent=2, ensure_ascii=False))
" 2>&1
fi
