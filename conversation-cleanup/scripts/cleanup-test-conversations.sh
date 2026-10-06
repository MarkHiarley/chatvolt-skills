#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Cleanup Test Conversations
# Usage: ./cleanup-test-conversations.sh <api-key> <org-id>
#
# Deleta TODAS as conversas de canal 'api' (conversas de teste).
# Pergunta confirmação antes de deletar.

API_KEY="${1:?Usage: $0 <api-key> <org-id>}"
ORG_ID="${2:?Usage: $0 <api-key> <org-id>}"
BASE_URL="https://api.chatvolt.ai"

echo "Buscando conversas de teste (canal api)..." >&2

CONVERSATIONS=$(curl -s "${BASE_URL}/conversation?organizationId=${ORG_ID}&limit=100" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json")

# Extract test conversation IDs
TEST_IDS=$(echo "$CONVERSATIONS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
test_convs = [c for c in data if c.get('channel') == 'api']
if not test_convs:
    print('NENHUMA')
    sys.exit(0)
for c in test_convs:
    created = c.get('createdAt', '?')[:16].replace('T', ' ')
    print(f'{c[\"id\"]}  ({created})')
")

if [ "$TEST_IDS" = "NENHUMA" ]; then
  echo "Nenhuma conversa de teste encontrada."
  exit 0
fi

echo ""
echo "Conversas de teste encontradas:"
echo "$TEST_IDS"
echo ""
echo "ATENÇÃO: Isso vai deletar TODAS as conversas acima."
echo "Digite 'sim' para confirmar:"
read -r CONFIRM
if [ "$CONFIRM" != "sim" ]; then
  echo "Cancelado."
  exit 1
fi

# Delete each one
echo "$CONVERSATIONS" | python3 -c "
import json, sys, urllib.request

data = json.load(sys.stdin)
test_convs = [c for c in data if c.get('channel') == 'api']
api_key = '$API_KEY'
base_url = '$BASE_URL'

deleted = 0
for c in test_convs:
    cid = c['id']
    req = urllib.request.Request(
        f'{base_url}/conversation/{cid}',
        method='DELETE',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        }
    )
    try:
        resp = json.loads(urllib.request.urlopen(req).read())
        if resp.get('success'):
            deleted += 1
            print(f'  ✅ {cid}')
        else:
            print(f'  ❌ {cid}: {resp.get(\"message\", \"erro\")}')
    except Exception as e:
        print(f'  ❌ {cid}: {e}')

print(f'\n{deleted} conversas deletadas.')
" 2>&1
