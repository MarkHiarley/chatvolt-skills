#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Get Tool Details
# Usage: ./get-tool.sh <api-key> <agent-id> <tool-id>

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <tool-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <tool-id>}"
TOOL_ID="${3:?Usage: $0 <api-key> <agent-id> <tool-id>}"
BASE_URL="https://api.chatvolt.ai"

echo "Fetching tool: ${TOOL_ID}" >&2

curl -s "${BASE_URL}/api/agents/${AGENT_ID}/tools/${TOOL_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | python3 -c "
import json, sys

data = json.load(sys.stdin)

# Handle error responses
if isinstance(data, dict) and ('error' in data or 'message' in data):
    err = data.get('error') or data.get('message') or str(data)
    print(f'ERROR: {err}')
    sys.exit(1)

print(json.dumps(data, indent=2, ensure_ascii=False))
" 2>&1
