#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Delete Conversation
# Usage: ./delete-conversation.sh <api-key> <conversation-id>
#
# ⚠️  Só use em conversas de TESTE (canal api). NÃO use em conversas reais.

API_KEY="${1:?Usage: $0 <api-key> <conversation-id>}"
CONV_ID="${2:?Usage: $0 <api-key> <conversation-id>}"
BASE_URL="https://api.chatvolt.ai"

echo "Deletando conversa: ${CONV_ID}" >&2

RESULT=$(curl -s -X DELETE "${BASE_URL}/conversation/${CONV_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json")

echo "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('success'):
    print(f\"✅ Conversa {data.get('conversationId', CONV_ID)} deletada.\")
else:
    print(f\"❌ ERRO: {data.get('message', 'desconhecido')}\")
    sys.exit(1)
"
