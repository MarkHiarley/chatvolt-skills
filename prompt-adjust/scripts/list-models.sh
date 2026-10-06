#!/usr/bin/env bash
set -euo pipefail

# Chatvolt List Models
# Usage: ./list-models.sh <api-key>
# Lista os modelos disponiveis (GET /agents/models)

API_KEY="${1:?Usage: $0 <api-key>}"
BASE_URL="https://api.chatvolt.ai"

curl -s "${BASE_URL}/agents/models" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | python3 -m json.tool
