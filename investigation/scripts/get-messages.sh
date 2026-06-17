#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Get Conversation Messages
# Usage: ./get-messages.sh <api-key> <conversation-id> [count]
#   count: Number of recent messages to retrieve (default: 50)

API_KEY="${1:?Usage: $0 <api-key> <conversation-id> [count]}"
CONVERSATION_ID="${2:?Usage: $0 <api-key> <conversation-id> [count]}"
COUNT="${3:-50}"
BASE_URL="https://api.chatvolt.ai"

echo "Fetching ${COUNT} messages from conversation: ${CONVERSATION_ID}" >&2

RESULT=$(curl -sf "${BASE_URL}/conversation/${CONVERSATION_ID}/messages/${COUNT}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json") || {
  echo "Error: Failed to fetch messages" >&2
  exit 1
}

# Format messages for easy reading
echo "${RESULT}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
msgs = data.get('messages', []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
print(f'Conversation: {data.get(\"id\", CONVERSATION_ID) if isinstance(data, dict) else CONVERSATION_ID}')
print(f'Messages: {len(msgs)}')
print('=' * 60)
for m in msgs:
    role = m.get('from', 'system')
    text = m.get('text', '')
    created = m.get('createdAt', '')
    if not text.strip():
        continue
    role_label = 'AGENT' if role == 'agent' else ('HUMAN' if role == 'human' else role.upper())
    print(f'[{role_label}] {created}')
    print(f'{text}')
    print('-' * 40)
" 2>/dev/null
