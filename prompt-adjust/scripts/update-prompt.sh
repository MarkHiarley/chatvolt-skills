#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Update System Prompt
# Usage: ./update-prompt.sh <api-key> <agent-id> <system-prompt>

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <system-prompt>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <system-prompt>}"
NEW_PROMPT="${3:?Usage: $0 <api-key> <agent-id> <system-prompt>}"
BASE_URL="https://api.chatvolt.ai"

echo "Updating system prompt for agent: ${AGENT_ID}" >&2

# Escape for JSON
ESCAPED=$(python3 -c "
import json, sys
prompt = sys.argv[1]
print(json.dumps(prompt))
" "$NEW_PROMPT")

RESULT=$(curl -s -X PATCH "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"systemPrompt\": ${ESCAPED}}")

# Check for errors
echo "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
err = data.get('error') or data.get('message')
if err:
    print(f'ERROR: {err}')
    sys.exit(1)
prompt = data.get('systemPrompt', '')
print(f'✅ System prompt atualizado com sucesso!')
print(f'   Novo tamanho: {len(prompt)} caracteres')
print(f'   Timestamp:    {data.get(\"updatedAt\", \"?\")}')
" 2>&1
