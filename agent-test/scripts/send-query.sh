#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Send Query
# Usage:
#   ./send-query.sh <api-key> <agent-id> <query>                   (cria nova conversa - PREFERIDO)
#   ./send-query.sh <api-key> <agent-id> <query> <conversation-id> (continua conversa - ⚠️ PERIGO!)
#   ./send-query.sh <api-key> <agent-id> <query> <conv-id> <temp> [model]
#
# ⚠️  AVISO: Enviar query em conversa existente SALVA A MENSAGEM no histórico real.
#    Só use com autorização explícita do usuário.

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <query> [conversation-id] [temperature] [model]}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <query> [conversation-id] [temperature] [model]}"
QUERY="${3:?Usage: $0 <api-key> <agent-id> <query> [conversation-id] [temperature] [model]}"
CONVERSATION_ID="${4:-}"
TEMP="${5:-}"
MODEL="${6:-}"
BASE_URL="https://api.chatvolt.ai"

# Safety check: warn if using existing conversation
if [ -n "$CONVERSATION_ID" ]; then
  echo "⚠️  ATENÇÃO: Enviando mensagem para conversa EXISTENTE: $CONVERSATION_ID" >&2
  echo "   A mensagem será SALVA no histórico real do Chatvolt!" >&2
  echo "   Pressione Ctrl+C para cancelar (5s)..." >&2
  sleep 5
fi

# Build JSON body
BODY=$(python3 -c "
import json

payload = {
    'query': '$QUERY'
}

if '$CONVERSATION_ID':
    payload['conversationId'] = '$CONVERSATION_ID'

if '$TEMP':
    payload['temperature'] = float('$TEMP')

if '$MODEL':
    payload['modelName'] = '$MODEL'

print(json.dumps(payload))
")

RESPONSE=$(curl -s -X POST "${BASE_URL}/agents/${AGENT_ID}/query" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$BODY")

echo "$RESPONSE" | python3 -c "
import json, sys

data = json.load(sys.stdin)

# Handle error
if 'error' in data or 'message' in data:
    err = data.get('error') or data.get('message') or str(data)
    print(f'ERROR: {err}')
    sys.exit(1)

answer = data.get('answer', data.get('response', data.get('text', '(no answer field)')))
conv_id = data.get('conversationId', '(no conversationId)')
print(json.dumps({
    'conversationId': conv_id,
    'answer': answer
}, indent=2, ensure_ascii=False))
" 2>&1
