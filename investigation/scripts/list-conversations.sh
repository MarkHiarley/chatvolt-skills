#!/usr/bin/env bash
set -euo pipefail

# Chatvolt List Conversations
# Usage: ./list-conversations.sh <api-key> <agent-id> [days-back] [limit] [status]
#   days-back: Number of days to look back (default: 7)
#   limit: Max conversations (default: 25, max: 100)
#   status: Filter by status (open, closed, waiting)

API_KEY="${1:?Usage: $0 <api-key> <agent-id> [days-back] [limit] [status]}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> [days-back] [limit] [status]}"
DAYS_BACK="${3:-7}"
LIMIT="${4:-25}"
STATUS="${5:-}"
BASE_URL="https://api.chatvolt.ai"

# Calculate start date
if [[ "$(uname)" == "Darwin" ]]; then
  START_DATE=$(date -u -v-${DAYS_BACK}d "+%Y-%m-%dT00:00:00.000Z")
else
  START_DATE=$(date -u -d "${DAYS_BACK} days ago" "+%Y-%m-%dT00:00:00.000Z" 2>/dev/null || date -u -d "-${DAYS_BACK} days" "+%Y-%m-%dT00:00:00.000Z")
fi

echo "Listing conversations for agent ${AGENT_ID} since ${START_DATE}" >&2

# Build query params
QUERY_PARAMS="agentId=${AGENT_ID}&createdAt=${START_DATE}&limit=${LIMIT}"
if [ -n "$STATUS" ]; then
  QUERY_PARAMS="${QUERY_PARAMS}&status=${STATUS}"
fi

curl -s "${BASE_URL}/conversation?${QUERY_PARAMS}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | python3 -m json.tool 2>/dev/null || {
  echo "Error: Failed to list conversations" >&2
  exit 1
}
