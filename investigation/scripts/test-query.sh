#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Test Query
# Sends a test question to the agent to verify its behavior
# Usage: ./test-query.sh <api-key> <agent-id> <query> [temperature]

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <query> [temperature]}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <query> [temperature]}"
QUERY="${3:?Usage: $0 <api-key> <agent-id> <query> [temperature]}"
TEMPERATURE="${4:-}"
BASE_URL="https://api.chatvolt.ai"

echo "Sending test query to agent ${AGENT_ID}..." >&2
echo "Query: ${QUERY}" >&2
[ -n "$TEMPERATURE" ] && echo "Temperature: ${TEMPERATURE}" >&2
echo "" >&2

# Build request body
BODY=$(python3 -c "
import json
body = {'query': '${QUERY}', 'streaming': false}
if '${TEMPERATURE}':
    body['temperature'] = ${TEMPERATURE}
print(json.dumps(body))
")

curl -s -X POST "${BASE_URL}/agents/${AGENT_ID}/query" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "${BODY}" | python3 -m json.tool 2>/dev/null || {
  echo "Error: Failed to send query" >&2
  exit 1
}
