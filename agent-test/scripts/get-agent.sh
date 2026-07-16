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

if 'error' in data or 'message' in data:
    err = data.get('error') or data.get('message') or str(data)
    print(f'ERROR: {err}')
    sys.exit(1)

print('═══════════════════════════════════════════')
print(f'  Agent:    {data.get(\"name\", \"N/A\")}')
print(f'  ID:       {data.get(\"id\", \"N/A\")}')
print(f'  Handle:   {data.get(\"handle\", \"N/A\")}')
print(f'  Model:    {data.get(\"modelName\", \"N/A\")}')
print(f'  Temp:     {data.get(\"temperature\", \"N/A\")}')
print(f'  Visib:    {data.get(\"visibility\", \"N/A\")}')
tools = data.get('tools', [])
tool_types = ', '.join(t.get('type','?') for t in tools)
print(f'  Tools:    {len(tools)} ({tool_types})')
print('═══════════════════════════════════════════')

if tools:
    print()
    print('Tools:')
    for t in tools:
        ttype = t.get('type', '?')
        tid = t.get('id', '?')
        config = t.get('config', {})
        name = config.get('name', '')
        if ttype == 'datastore':
            dsid = t.get('datastoreId', '?')
            print(f'  - datastore [{dsid}]')
        elif ttype == 'http':
            print(f'  - http: {name}')
            print(f'      {config.get(\"url\", \"\")}')
        elif ttype == 'form':
            print(f'  - form [{t.get(\"formId\", \"?\")}]')
        else:
            print(f'  - {ttype}: {tid}')

prompt = data.get('systemPrompt')
print()
if prompt:
    print(f'System Prompt ({len(prompt)} chars):')
    print('\"\"\"')
    print(prompt)
    print('\"\"\"')
else:
    print('System Prompt: (none)')
"
