#!/usr/bin/env bash
set -euo pipefail

# Chatvolt List Conversations
# Usage: ./list-conversations.sh <api-key> <org-id> [limit]
#   limit: max conversations to show (default: 20)

API_KEY="${1:?Usage: $0 <api-key> <org-id> [limit]}"
ORG_ID="${2:?Usage: $0 <api-key> <org-id> [limit]}"
LIMIT="${3:-20}"
BASE_URL="https://api.chatvolt.ai"

echo "Fetching up to ${LIMIT} conversations..." >&2

curl -s "${BASE_URL}/conversation?organizationId=${ORG_ID}&limit=${LIMIT}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Total: {len(data)} conversas')
print()
for c in data:
    cid = c['id']
    channel = c.get('channel', '?')
    status = c.get('status', '?')
    agent_id = c.get('agentId', '?')[:20]
    created = c.get('createdAt', '?')[:16].replace('T', ' ')
    contacts = c.get('participantsContacts', [])
    name = contacts[0].get('firstName', '?') if contacts else '?'
    ai = '🤖' if c.get('isAiEnabled') else ' '
    print(f'{ai} [{channel:10}] {cid}')
    print(f'   {status:10} | {created} | {name}')
    print(f'   agent: {agent_id}')
    print()
" 2>/dev/null
