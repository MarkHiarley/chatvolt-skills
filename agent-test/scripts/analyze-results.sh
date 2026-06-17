#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Analyze Conversation
# Usage: ./analyze-results.sh <api-key> <agent-id> <conversation-id> <history-file>
#
# The history-file should be a JSON file with the conversation history
# (array of {role, content} objects).

API_KEY="${1:?Usage: $0 <api-key> <agent-id> <conversation-id> <history-file> <fluxo-esperado>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id> <conversation-id> <history-file> <fluxo-esperado>}"
CONVERSATION_ID="${3:?Usage: $0 <api-key> <agent-id> <conversation-id> <history-file> <fluxo-esperado>}"
HISTORY_FILE="${4:?Usage: $0 <api-key> <agent-id> <conversation-id> <history-file> <fluxo-esperado>}"
FLUXO_ESPERADO="${5:-}"

if [ ! -f "$HISTORY_FILE" ]; then
  echo "ERROR: History file not found: $HISTORY_FILE"
  exit 1
fi

# If no fluxo provided via arg, read from stdin or prompt
if [ -z "$FLUXO_ESPERADO" ]; then
  echo "Enter the expected flow/rules to check against:"
  read -r FLUXO_ESPERADO
fi

# Also get agent info to include system prompt
BASE_URL="https://api.chatvolt.ai"
AGENT_INFO=$(curl -s "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json")

SYSTEM_PROMPT=$(echo "$AGENT_INFO" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('systemPrompt', '(none)'))
")

echo ""
echo "═══ Análise de Conformidade ═══"
echo ""
echo "Agente: ${AGENT_ID}"
echo "Conversa: ${CONVERSATION_ID}"
echo ""
echo "System Prompt:"
echo "${SYSTEM_PROMPT}" | head -c 500
echo ""
echo ""
echo "Fluxo Esperado:"
echo "${FLUXO_ESPERADO}"
echo ""

# Analyze using python
python3 -c "
import json, sys

with open('$HISTORY_FILE') as f:
    history = json.load(f)

fluxo = '''$FLUXO_ESPERADO'''

messages = history if isinstance(history, list) else history.get('messages', [])

if not messages:
    print('No messages in history.')
    sys.exit(0)

print(f'Analyzing {len(messages)} messages...')
print()

# Simplified analysis: look for patterns in the conversation
# Count messages by role
user_msgs = [m for m in messages if m.get('role') == 'user' or m.get('role') == 'USER']
assistant_msgs = [m for m in messages if m.get('role') == 'assistant' or m.get('role') == 'ASSISTANT' or m.get('role') == 'bot']

print(f'User messages:      {len(user_msgs)}')
print(f'Assistant messages: {len(assistant_msgs)}')
print()

# Generate analysis prompts for the user to consider
print('─── Pontos para verificar ───')
print()

rules = [r.strip() for r in fluxo.split(',') if r.strip()]
rules = [r for r in rules if len(r) > 5]
if not rules:
    # Try line by line
    rules = [r.strip() for r in fluxo.split(chr(10)) if r.strip() and len(r.strip()) > 5]

for i, msg in enumerate(assistant_msgs):
    content = msg.get('content', msg.get('text', ''))
    print(f'--- Resposta do Assistente #{i+1} ---')
    # Truncate for display
    display = content[:600] + ('...' if len(content) > 600 else '')
    print(display)
    print()

    # Check each rule
    for r in rules:
        rl = r.lower()
        content_lower = content.lower()
        
        # Simple heuristics for common checks
        checks = []
        
        # Language check
        if 'portugu' in rl or 'português' in rl or 'portugues' in rl:
            # Check if response has Portuguese-specific characters
            has_pt = any(c in content_lower for c in ['ão', 'ç', 'ê', 'õ', 'é', 'á', 'í', 'ó', 'ú'])
            checks.append(('✅' if has_pt else '⚠️', f'Respondeu em português: {\"sim\" if has_pt else \"não parece\"}'))
        
        # Check for specific phrases/words mentioned in rules
        words_to_check = []
        if 'não' in rl and ('mencion' in rl or 'fale' in rl or 'cite' in rl):
            words_to_check.append(('concorrente', '⚠️ Mencionou concorrentes?'))
        if 'se apresent' in rl:
            words_to_check.append(('assistente', '✅ Se apresentou como assistente'))
        if 'site' in rl:
            words_to_check.append(('site', '✅ Mencionou o site'))
        
        for word, label in words_to_check:
            found = word in content_lower
            if found:
                print(f'   {label}')

print()
print('─── Análise baseada em IA ───')
print()
print('Para uma análise mais precisa, copie o histórico acima e')
print('pergunta ao seu LLM: \"Este agente está seguindo estas regras?\"')
print()
print(f'Regras: {fluxo}')
" 2>&1

echo ""
echo "═══ Fim da Análise ═══"
