#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Full Adjustment Workflow
# Usage: ./adjust.sh <api-key> <agent-id> <query-de-teste>

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <query-de-teste>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <query-de-teste>}"
TEST_QUERY="${3:?Usage: $0 <api-key> <agent-id> <query-de-teste>}"
BASE_URL="https://api.chatvolt.ai"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Chatvolt Agent Adjustment Workflow${NC}"
echo -e "${CYAN}============================================${NC}"
echo "Agent ID: ${AGENT_ID}"
echo "Test Query: ${TEST_QUERY}"
echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# ── Step 1: Get Current Config ─────────────────────────────────────────────
echo -e "${YELLOW}▶ Step 1/5: Fetching current agent configuration...${NC}"
echo "----------------------------------------"

AGENT_DATA=$(curl -sf "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json") || {
  echo -e "${RED}ERROR: Failed to fetch agent. Check API key and agent ID.${NC}"
  exit 1
}

CURRENT_MODEL=$(echo "$AGENT_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('modelName','?'))")
CURRENT_TEMP=$(echo "$AGENT_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('temperature','?'))")
CURRENT_PROMPT=$(echo "$AGENT_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('systemPrompt','') or '')")
PROMPT_LEN=$(echo "$CURRENT_PROMPT" | wc -c)

echo -e "${GREEN}Model:${NC}       ${CURRENT_MODEL}"
echo -e "${GREEN}Temperature:${NC} ${CURRENT_TEMP}"
echo -e "${GREEN}Prompt size:${NC} ${PROMPT_LEN} chars"
echo ""

# Save current config for comparison
echo "$AGENT_DATA" > /tmp/chatvolt-adjust-before.json

# ── Step 2: Test with Current Config ────────────────────────────────────────
echo -e "${YELLOW}▶ Step 2/5: Testing agent with query '${TEST_QUERY}'...${NC}"
echo "----------------------------------------"

CURRENT_RESPONSE=$(curl -s -X POST "${BASE_URL}/agents/${AGENT_ID}/query" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "import json; print(json.dumps({'query': '${TEST_QUERY}', 'streaming': False}))")")

REPLY=$(echo "$CURRENT_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
reply = data.get('answer') or data.get('reply') or data.get('text') or data.get('response') or 'N/A'
print(reply[:800])
")
echo -e "${CYAN}Response:${NC}"
echo "$REPLY"
echo ""

# ── Step 3: Edit System Prompt ─────────────────────────────────────────────
echo -e "${YELLOW}▶ Step 3/5: System prompt adjustments${NC}"
echo "----------------------------------------"

# Save prompt to temp file
echo "$CURRENT_PROMPT" > /tmp/chatvolt-prompt-atual.txt
echo "Current prompt saved to /tmp/chatvolt-prompt-atual.txt"
echo ""

# Determine what to change based on analysis
echo "Checking for common issues..."
ISSUES=""

if echo "$CURRENT_PROMPT" | grep -qi "gemini_flash_preview"; then
    ISSUES="${ISSUES}- Modelo Gemini Flash Preview pode ignorar instruções complexas\n"
fi

if [ "$(echo "$CURRENT_TEMP" | python3 -c "print(float(input()) > 0.1)")" = "True" ]; then
    ISSUES="${ISSUES}- Temperatura ${CURRENT_TEMP} pode estar alta para um fluxo determinístico\n"
fi

# Check if the critical instruction about numbers is present
if echo "$CURRENT_PROMPT" | grep -q "não interprete isso como a resposta do usuário"; then
    ISSUES="${ISSUES}- Regra sobre números existe mas pode estar muito no final do prompt\n"
fi

if [ -n "$ISSUES" ]; then
    echo -e "${YELLOW}Possible issues detected:${NC}"
    echo -e "$ISSUES"
else
    echo -e "${GREEN}No obvious issues detected in configuration.${NC}"
fi

echo ""

# ── Step 4: Interactive Adjustments ────────────────────────────────────────
echo -e "${YELLOW}▶ Step 4/5: Apply adjustments${NC}"
echo "----------------------------------------"
echo "Choose what to change:"
echo "  1) Update system prompt (from /tmp/chatvolt-novo-prompt.txt)"
echo "  2) Change model"
echo "  3) Change temperature"
echo "  4) All of the above"
echo "  5) Skip - just test"
echo ""

# If a file /tmp/chatvolt-novo-prompt.txt already exists, use it
if [ -f /tmp/chatvolt-novo-prompt.txt ]; then
    echo -e "${GREEN}Found /tmp/chatvolt-novo-prompt.txt - will use it for prompt update${NC}"
    echo ""
    DIFF=$(diff /tmp/chatvolt-prompt-atual.txt /tmp/chatvolt-novo-prompt.txt 2>/dev/null || echo "different")
    if [ -n "$DIFF" ]; then
        echo "Differences from current prompt:"
        diff /tmp/chatvolt-prompt-atual.txt /tmp/chatvolt-novo-prompt.txt 2>/dev/null | head -50 || true
        echo ""
    fi
fi

echo -e "${CYAN}To make changes, create/modify files:${NC}"
echo "  - System prompt: /tmp/chatvolt-novo-prompt.txt"
echo "  - Then re-run this script"
echo ""

# ── Step 5: Final Test ──────────────────────────────────────────────────────
echo -e "${YELLOW}▶ Step 5/5: Final configuration summary${NC}"
echo "----------------------------------------"

# Re-fetch to show current state
AGENT_DATA_NOW=$(curl -sf "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json") || true

NEW_MODEL=$(echo "$AGENT_DATA_NOW" | python3 -c "import json,sys; print(json.load(sys.stdin).get('modelName','?'))" 2>/dev/null || echo "?")
NEW_TEMP=$(echo "$AGENT_DATA_NOW" | python3 -c "import json,sys; print(json.load(sys.stdin).get('temperature','?'))" 2>/dev/null || echo "?")
NEW_PROMPT_LEN=$(echo "$AGENT_DATA_NOW" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('systemPrompt','') or ''))" 2>/dev/null || echo "?")

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Adjustment Report${NC}"
echo -e "${CYAN}============================================${NC}"

echo ""
echo "Before → After:"
echo -e "  Model:        ${CURRENT_MODEL} → ${NEW_MODEL}"
echo -e "  Temperature:  ${CURRENT_TEMP} → ${NEW_TEMP}"
echo -e "  Prompt size:  ${PROMPT_LEN} → ${NEW_PROMPT_LEN} chars"

if [ "$CURRENT_MODEL" != "$NEW_MODEL" ] || [ "$CURRENT_TEMP" != "$NEW_TEMP" ] || [ "$PROMPT_LEN" != "$NEW_PROMPT_LEN" ]; then
    echo ""
    echo -e "${GREEN}✅ Changes detected and applied.${NC}"
else
    echo ""
    echo -e "${YELLOW}ℹ️  No changes applied. Edit /tmp/chatvolt-novo-prompt.txt and re-run.${NC}"
fi

echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "1. Edit the prompt:  nano /tmp/chatvolt-novo-prompt.txt"
echo "2. Re-run:           $0 \"$API_KEY\" \"$AGENT_ID\" \"$TEST_QUERY\""
echo "3. Test with query:  ${SCRIPT_DIR}/test-query.sh \"$API_KEY\" \"$AGENT_ID\" \"$TEST_QUERY\""
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Complete${NC}"
echo -e "${CYAN}============================================${NC}"
