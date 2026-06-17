#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Agent Details Fetcher
# Usage: ./agent.sh <api-key> <agent-id>
#   agent-id: UUID or handle prefixed with @ (e.g., @my-agent)

API_KEY="${1:?Usage: $0 <api-key> <agent-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id>}"
BASE_URL="https://api.chatvolt.ai"

echo "Fetching agent details: ${AGENT_ID}" >&2

curl -s "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | python3 -m json.tool 2>/dev/null || {
  echo "Error: Failed to fetch agent details" >&2
  exit 1
}
