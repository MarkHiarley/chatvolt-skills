#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Full Agent Investigation
# Usage: ./investigate.sh <api-key> <agent-id> [days-back] [limit]
#   days-back: Number of days to look back for conversations (default: 7)
#   limit: Max conversations to analyze (default: 10)

API_KEY="${1:?Usage: $0 <api-key> <agent-id> [days-back] [limit]}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> [days-back] [limit]}"
DAYS_BACK="${3:-7}"
LIMIT="${4:-10}"
BASE_URL="https://api.chatvolt.ai"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  Chatvolt Agent Investigation Report"
echo "============================================"
echo "Agent ID:    ${AGENT_ID}"
echo "Days Back:   ${DAYS_BACK}"
echo "Max Convos:  ${LIMIT}"
echo "Date:        $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "============================================"
echo ""

# ── Step 1: Fetch Agent Details ──────────────────────────────────────────
echo "▶ Step 1/3: Fetching agent configuration..."
echo "----------------------------------------"
AGENT_DATA=$(curl -sf "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json") || {
  echo "ERROR: Failed to fetch agent details. Check API key and agent ID."
  exit 1
}

echo "${AGENT_DATA}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Name:           {data.get(\"name\", \"N/A\")}')
print(f'Handle:         {data.get(\"handle\", \"N/A\")}')
print(f'Model:          {data.get(\"modelName\", \"N/A\")}')
print(f'Temperature:    {data.get(\"temperature\", \"N/A\")}')
print(f'Visibility:     {data.get(\"visibility\", \"N/A\")}')
print(f'Created:        {data.get(\"createdAt\", \"N/A\")}')
print(f'Updated:        {data.get(\"updatedAt\", \"N/A\")}')
tools = data.get('tools', [])
print(f'Tools:          {len(tools)} configured')
for t in tools:
    print(f'  - {t.get(\"type\", \"unknown\")}: {t.get(\"name\", \"unnamed\")}')
sys_prompt = data.get('systemPrompt')
if sys_prompt:
    print(f'\\nSystem Prompt ({len(sys_prompt)} chars):')
    print('\"\"\"')
    print(sys_prompt)
    print('\"\"\"')
else:
    print('\\nSystem Prompt: (none)')
" 2>&1

echo ""
echo "----------------------------------------"
echo ""

# ── Step 2: List Recent Conversations ────────────────────────────────────
echo "▶ Step 2/3: Listing recent conversations..."
echo "----------------------------------------"

# Calculate start date
if [[ "$(uname)" == "Darwin" ]]; then
  START_DATE=$(date -u -v-${DAYS_BACK}d "+%Y-%m-%dT00:00:00.000Z")
else
  START_DATE=$(date -u -d "${DAYS_BACK} days ago" "+%Y-%m-%dT00:00:00.000Z" 2>/dev/null || date -u -d "-${DAYS_BACK} days" "+%Y-%m-%dT00:00:00.000Z")
fi

CONVERSATIONS=$(curl -sf "${BASE_URL}/conversation?agentId=${AGENT_ID}&createdAt=${START_DATE}&limit=${LIMIT}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json") || {
  echo "WARNING: Failed to list conversations."
  CONVERSATIONS="[]"
}

CONV_COUNT=$(echo "${CONVERSATIONS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if isinstance(data, list):
    print(len(data))
elif isinstance(data, dict):
    # Try common pagination formats
    print(len(data.get('data', data.get('results', []))))
else:
    print(0)
" 2>/dev/null || echo "0")

echo "Found ${CONV_COUNT} conversations in the last ${DAYS_BACK} days."

# Extract conversation IDs
CONV_IDS=$(echo "${CONVERSATIONS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('data', [])
for c in items:
    cid = c.get('id', '')
    status = c.get('status', 'unknown')
    cdate = c.get('createdAt', '')
    print(f'{cid}|{status}|{cdate}')
" 2>/dev/null || true)

echo ""

# ── Step 3: Get Messages from each conversation ──────────────────────────
echo "▶ Step 3/3: Analyzing conversation messages..."
echo "----------------------------------------"

if [ -z "$CONV_IDS" ]; then
  echo "No conversations to analyze."
  echo ""
  echo "============================================"
  echo "  Investigation Complete"
  echo "============================================"
  exit 0
fi

echo "${CONV_IDS}" | while IFS='|' read -r CID STATUS CDATE; do
  [ -z "$CID" ] && continue
  echo ""
  echo "─── Conversation: ${CID} ──────────────────"
  echo "Status: ${STATUS:-N/A}"
  echo "Created: ${CDATE:-N/A}"
  echo ""

  # Get last 20 messages from each conversation
  MSGS=$(curl -sf "${BASE_URL}/conversation/${CID}/messages/20" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json") || {
    echo "  (could not fetch messages)"
    continue
  }

  # Display messages for analysis
  echo "${MSGS}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
messages = data.get('messages', []) if isinstance(data, dict) else (data if isinstance(data, list) else [])

for m in messages:
    role = m.get('from', 'system')
    content = m.get('text', '')
    created = m.get('createdAt', '')
    # Skip empty messages
    if not content.strip():
        continue
    # Truncate very long messages
    if len(content) > 500:
        content = content[:500] + '... [truncated]'
    # Map 'from' values to readable roles
    role_label = 'AGENT' if role == 'agent' else ('HUMAN' if role == 'human' else role.upper())
    print(f'  [{role_label}] {created}')
    print(f'  {content}')
    print()
" 2>/dev/null

  echo "──────────────────────────────────────────"
done

echo ""
echo "============================================"
echo "  Investigation Complete"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Review the agent's system prompt against its actual responses"
echo "2. Check if the agent stays in character and follows instructions"
echo "3. Verify tool usage matches configuration"
echo "4. Look for hallucinations or incorrect information"
echo "5. Assess response quality and appropriateness"
echo "============================================"
