#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Get Agent Config
# Usage: ./get-agent.sh <api-key> <agent-id>

API_KEY="${1:?Usage: $0 <api-key> <agent-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id>}"
BASE_URL="https://api.chatvolt.ai"

echo "Fetching agent details: ${AGENT_ID}" >&2

curl -s "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | python3 -c "
import json, sys

data = json.load(sys.stdin)

print('=' * 60)
print(f'  Agent:    {data.get(\"name\", \"N/A\")}')
print(f'  ID:       {data.get(\"id\", \"N/A\")}')
print(f'  Model:    {data.get(\"modelName\", \"N/A\")}')
print(f'  Temp:     {data.get(\"temperature\", \"N/A\")}')
print(f'  Visib:    {data.get(\"visibility\", \"N/A\")}')
print('=' * 60)

tools = data.get('tools', [])
print(f'\nTools ({len(tools)}):')
for t in tools:
    print(f'  - {t.get(\"type\", \"unknown\")}: {t.get(\"id\", \"?\")}')
    if t.get('type') == 'datastore' and t.get('datastore'):
        print(f'      datastore: {t[\"datastore\"].get(\"name\", \"?\")}')

prompt = data.get('systemPrompt')
if prompt:
    print(f'\nSystem Prompt ({len(prompt)} chars):')
    print('\"\"\"')
    print(prompt)
    print('\"\"\"')
else:
    print('\nSystem Prompt: (none)')
" 2>/dev/null || {
  echo "Error: Failed to fetch agent details"
  curl -s "${BASE_URL}/agents/${AGENT_ID}" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json"
  exit 1
}
