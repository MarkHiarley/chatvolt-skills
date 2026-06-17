#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Update Temperature
# Usage: ./update-temperature.sh <api-key> <agent-id> <temperature>

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <temperature>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <temperature>}"
TEMP="${3:?Usage: $0 <api-key> <agent-id> <temperature>}"
BASE_URL="https://api.chatvolt.ai"

# Validate temperature
python3 -c "
t = float('${TEMP}')
if t < 0.0 or t > 1.0:
    print('ERROR: Temperature must be between 0.0 and 1.0')
    exit(1)
" 2>&1 || exit 1

echo "Updating temperature to ${TEMP} for agent: ${AGENT_ID}" >&2

RESULT=$(curl -s -X PATCH "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'temperature': float('${TEMP}')}))")")

echo "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
err = data.get('error') or data.get('message')
if err:
    print(f'ERROR: {err}')
    sys.exit(1)
temp = data.get('temperature', '?')
print(f'✅ Temperatura atualizada com sucesso!')
print(f'   Temperatura: {temp}')
print(f'   Timestamp:   {data.get(\"updatedAt\", \"?\")}')
" 2>&1
