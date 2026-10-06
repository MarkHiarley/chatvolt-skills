#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Set Webhook
# Usage: ./set-webhook.sh <api-key> <agent-id> <json-body>
#   json-body: corpo JSON da configuracao do webhook (POST /agents/{id}/webhook)
#   Ex: '{"url":"https://exemplo.com/hook"}'

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <json-body>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <json-body>}"
BODY="${3:?Usage: $0 <api-key> <agent-id> <json-body>}"
BASE_URL="https://api.chatvolt.ai"

echo "Configurando webhook do agente: ${AGENT_ID}" >&2

curl -s -X POST "${BASE_URL}/agents/${AGENT_ID}/webhook" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY" | python3 -m json.tool
