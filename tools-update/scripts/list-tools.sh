#!/usr/bin/env bash
set -euo pipefail

# Chatvolt List Tools
# Usage: ./list-tools.sh <api-key> <agent-id>

API_KEY="${1:?Usage: $0 <api-key> <agent-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id>}"
BASE_URL="https://api.chatvolt.ai"

echo "Fetching tools for agent: ${AGENT_ID}" >&2

RESPONSE=$(curl -s "${BASE_URL}/api/agents/${AGENT_ID}/tools" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json")

# Check if response is an array
echo "$RESPONSE" | python3 -c "
import json, sys

data = json.load(sys.stdin)

# Handle error responses
if isinstance(data, dict) and ('error' in data or 'message' in data):
    err = data.get('error') or data.get('message') or str(data)
    print(f'ERROR: {err}')
    sys.exit(1)

if not isinstance(data, list):
    if isinstance(data, dict):
        # Might be wrapped in a data field
        inner = data.get('data') or data.get('tools') or data.get('results')
        if inner and isinstance(inner, list):
            data = inner
        else:
            print(f'Unexpected response format: {json.dumps(data, indent=2)}')
            sys.exit(1)
    else:
        print(f'Unexpected response: {data}')
        sys.exit(1)

if len(data) == 0:
    print('No tools configured for this agent.')
    sys.exit(0)

# Determine column widths
id_width = max(38, max((len(t.get('id', '')) for t in data), default=0) + 2)
type_width = max(10, max((len(t.get('type', '')) for t in data), default=0) + 2)
name_width = 34
desc_width = 40

# Header
sep = '+' + '-' * id_width + '+' + '-' * type_width + '+' + '-' * name_width + '+' + '-' * desc_width + '+'
print(sep)
print(f'| {\"Tool ID\":<{id_width-1}}| {\"Type\":<{type_width-1}}| {\"Name\":<{name_width-1}}| {\"Description\":<{desc_width-1}}|')
print(sep)

for t in data:
    tid = t.get('id', '')[:id_width-2]
    ttype = t.get('type', '')[:type_width-2]
    config = t.get('config', {})
    name = config.get('name', t.get('datastoreId', t.get('formId', '')))[:name_width-2]
    desc = config.get('description', '')[:desc_width-2]
    print(f'| {tid:<{id_width-1}}| {ttype:<{type_width-1}}| {name:<{name_width-1}}| {desc:<{desc_width-1}}|')

print(sep)
print(f'Total: {len(data)} tool(s)')
" 2>&1 || {
  # If python parsing fails, show raw response
  echo "Raw response:" >&2
  echo "$RESPONSE"
  exit 1
}
