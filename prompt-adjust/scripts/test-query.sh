#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Test Query
# Usage: ./test-query.sh <api-key> <agent-id> <query> [temperature] [model]

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <query> [temperature] [model]}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <query> [temperature] [model]}"
QUERY="${3:?Usage: $0 <api-key> <agent-id> <query> [temperature] [model]}"
TEMP="${4:-}"
MODEL="${5:-}"
BASE_URL="https://api.chatvolt.ai"

echo "Testing query for agent: ${AGENT_ID}" >&2
echo "Query: ${QUERY}" >&2
[ -n "$TEMP" ]  && echo "Temp override: ${TEMP}" >&2
[ -n "$MODEL" ] && echo "Model override: ${MODEL}" >&2
echo "---" >&2

# Build JSON body
BODY=$(python3 -c "
import json
body = {
    'query': '''${QUERY}''',
    'streaming': False
}
if '${TEMP}':
    body['temperature'] = float('${TEMP}')
if '${MODEL}':
    body['modelName'] = '${MODEL}'
print(json.dumps(body))
")

RESULT=$(curl -s -X POST "${BASE_URL}/agents/${AGENT_ID}/query" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

echo "$RESULT" | python3 -c "
import json, sys

data = json.load(sys.stdin)
err = data.get('error') or data.get('message')
if err:
    print(f'ERROR: {err}')
    sys.exit(1)

# Try different response formats used by Chatvolt API
reply = (data.get('answer') or 
         data.get('reply') or 
         data.get('text') or 
         data.get('response') or 
         data.get('content') or 
         str(data))

if isinstance(reply, str) and reply.startswith('{') and reply.endswith('}'):
    try:
        reply = json.loads(reply).get('text', reply)
    except:
        pass

print('=== RESPOSTA DO AGENTE ===')
print(reply)
print('=== FIM DA RESPOSTA ===')
" 2>&1
