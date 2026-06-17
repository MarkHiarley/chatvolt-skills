#!/usr/bin/env bash
set -euo pipefail

# Chatvolt Interactive Agent Tester
# Usage: ./test-agent.sh <api-key> <agent-id>
#
# Fluxo:
#   1. Busca config do agente
#   2. Pergunta o fluxo esperado
#   3. Inicia conversa (salva conversationId)
#   4. Loop: pergunta → resposta → ações
#   5. Ações: continuar, histórico, nova conversa, analisar, sair

API_KEY="${1:?Usage: $0 <api-key> <agent-id>}"
AGENT_ID="${2:?Usage: $0 <api-key> <agent-id>}"
BASE_URL="https://api.chatvolt.ai"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# State
CONVERSATION_ID=""
HISTORY_FILE=""
FLUXO_ESPERADO=""
SESSION_DIR=""

cleanup() {
  if [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ]; then
    rm -rf "$SESSION_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ─── Banner ──────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Chatvolt Agent Tester              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# ─── Step 1: Fetch agent config ─────────────────────────────────
echo -e "${BLUE}─── Buscando configuração do agente ───${NC}"
echo ""

AGENT_RESPONSE=$(curl -s "${BASE_URL}/agents/${AGENT_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json")

AGENT_NAME=$(echo "$AGENT_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'error' in data or 'message' in data:
    print('ERROR:' + (data.get('error') or data.get('message') or ''))
    sys.exit(0)
print(data.get('name', 'N/A'))
print(data.get('modelName', 'N/A'))
print(str(data.get('temperature', 'N/A')))
tools = data.get('tools', [])
print(str(len(tools)))
" 2>/dev/null || echo "ERROR")

if echo "$AGENT_NAME" | grep -q "^ERROR"; then
  ERR_MSG=$(echo "$AGENT_NAME" | sed 's/^ERROR://')
  echo -e "${RED}Erro ao buscar agente: ${ERR_MSG}${NC}"
  echo ""
  echo "Dica: verifique se o agent-id está correto e a API key tem acesso."
  exit 1
fi

AGENT_NAME=$(echo "$AGENT_NAME" | sed -n '1p')
AGENT_MODEL=$(echo "$AGENT_NAME" | sed -n '2p')
AGENT_TEMP=$(echo "$AGENT_NAME" | sed -n '3p')
AGENT_TOOLS=$(echo "$AGENT_NAME" | sed -n '4p')

echo -e "${GREEN}Agent: ${AGENT_NAME}${NC}"
echo -e "  ${YELLOW}Model:${NC} ${AGENT_MODEL}"
echo -e "  ${YELLOW}Temp:${NC}  ${AGENT_TEMP}"
echo -e "  ${YELLOW}Tools:${NC} ${AGENT_TOOLS}"
echo ""

# Extract and show system prompt
SYSTEM_PROMPT=$(echo "$AGENT_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('systemPrompt', '(none)'))
")

echo -e "${CYAN}System Prompt:${NC}"
echo -e "${MAGENTA}\"\"\"${NC}"
echo "$SYSTEM_PROMPT"
echo -e "${MAGENTA}\"\"\"${NC}"
echo ""

# ─── Step 2: Define expected flow ────────────────────────────────
echo -e "${BLUE}─── Configurar Teste ───${NC}"
echo ""
echo -e "Descreva o ${YELLOW}fluxo esperado${NC} — as regras que o agente deve seguir."
echo "Isso será usado depois para analisar se o comportamento está correto."
echo -e "(Ex: ${GREEN}\"Responder em português, se apresentar como assistente, nunca inventar preços\"${NC})"
echo ""
read -r -p "Fluxo esperado: " FLUXO_ESPERADO
echo ""

if [ -z "$FLUXO_ESPERADO" ]; then
  FLUXO_ESPERADO="(não definido)"
  echo -e "${YELLOW}Nenhum fluxo definido. A análise será genérica.${NC}"
  echo ""
fi

# ─── Step 3: Create session directory ───────────────────────────
SESSION_DIR=$(mktemp -d /tmp/chatvolt-test-XXXXXX)
HISTORY_FILE="${SESSION_DIR}/history.json"
echo '{"messages":[]}' > "$HISTORY_FILE"

# ─── Helper: Start a new conversation ────────────────────────────
start_new_conversation() {
  echo ""
  echo -e "${CYAN}─── Iniciando nova conversa ───${NC}"
  echo ""

  # Send an empty-ish query to just create a conversation
  # Actually, we'll use the first user message to create it
  CONVERSATION_ID=""
  echo '{"messages":[]}' > "$HISTORY_FILE"
  echo -e "${GREEN}Nova conversa pronta para começar!${NC}"
  echo ""
}

# ─── Helper: Send a query ────────────────────────────────────────
send_query() {
  local query="$1"
  local body

  body=$(python3 -c "
import json
payload = {'query': '$query'}
if '$CONVERSATION_ID':
    payload['conversationId'] = '$CONVERSATION_ID'
print(json.dumps(payload))
")

  local response
  response=$(curl -s -X POST "${BASE_URL}/agents/${AGENT_ID}/query" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$body")

  # Extract data
  local answer conv_id error_msg
  error_msg=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
err = data.get('error') or data.get('message') or ''
if err:
    print(err)
" 2>/dev/null || echo "")

  if [ -n "$error_msg" ]; then
    echo -e "${RED}Erro: ${error_msg}${NC}"
    return 1
  fi

  answer=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ans = data.get('answer') or data.get('response') or data.get('text') or json.dumps(data)
print(ans)
" 2>/dev/null || echo "(erro ao processar resposta)")

  conv_id=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('conversationId', ''))
" 2>/dev/null || echo "")

  # Store conversation ID
  if [ -n "$conv_id" ] && [ "$conv_id" != "$CONVERSATION_ID" ]; then
    CONVERSATION_ID="$conv_id"
    echo -e "${GREEN}Nova conversa iniciada: ${CONVERSATION_ID}${NC}"
    echo ""
  fi

  # Save to history
  python3 -c "
import json
with open('$HISTORY_FILE') as f:
    history = json.load(f)
if not isinstance(history, dict):
    history = {'messages': history if isinstance(history, list) else []}
history.setdefault('messages', []).append({'role': 'user', 'content': '$query'})
history['messages'].append({'role': 'assistant', 'content': '''$(echo "$answer" | sed "s/'/'\\\\''/g")'''})
with open('$HISTORY_FILE', 'w') as f:
    json.dump(history, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true

  # Print response
  echo -e "${YELLOW}Assistant:${NC}"
  echo "$answer"
  echo ""
}

# ─── Helper: Show history ────────────────────────────────────────
show_history() {
  echo ""
  echo -e "${CYAN}─── Histórico da Conversa ───${NC}"
  echo -e "Conversation ID: ${CONVERSATION_ID:-"(ainda não iniciada)"}"
  echo ""

  if [ ! -f "$HISTORY_FILE" ]; then
    echo "Nenhum histórico disponível."
    return
  fi

  python3 -c "
import json
with open('$HISTORY_FILE') as f:
    history = json.load(f)
msgs = history.get('messages', [])
if not msgs:
    print('Nenhuma mensagem ainda.')
else:
    for i, m in enumerate(msgs):
        role = m.get('role', '?').upper()
        content = m.get('content', '')
        prefix = '🧑 Você' if role == 'USER' else '🤖 Assistente'
        print(f'{'='*50}')
        print(f'{prefix} #{i//2 + 1}')
        print(f'{'='*50}')
        print(content[:800])
        if len(content) > 800:
            print('...[truncado]')
        print()
" 2>/dev/null || echo "(erro ao ler histórico)"
}

# ─── Helper: Analyze results ─────────────────────────────────────
analyze_results() {
  echo ""
  echo -e "${CYAN}─── Análise de Conformidade ───${NC}"
  echo ""

  if [ ! -f "$HISTORY_FILE" ]; then
    echo "Nenhum histórico para analisar."
    return
  fi

  # Count messages
  MSG_COUNT=$(python3 -c "
import json
with open('$HISTORY_FILE') as f:
    history = json.load(f)
print(len(history.get('messages', [])))
" 2>/dev/null || echo "0")

  if [ "$MSG_COUNT" -eq 0 ]; then
    echo "Nenhuma mensagem trocada ainda."
    return
  fi

  # Show agent info
  echo -e "${YELLOW}Agente:${NC} ${AGENT_NAME} (${AGENT_MODEL})"
  echo -e "${YELLOW}Conversa:${NC} ${CONVERSATION_ID}"
  echo -e "${YELLOW}Fluxo esperado:${NC} ${FLUXO_ESPERADO}"
  echo ""

  # Get the actual messages to analyze
  python3 -c "
import json
with open('$HISTORY_FILE') as f:
    history = json.load(f)
msgs = history.get('messages', [])

assistant_msgs = [m for m in msgs if m.get('role') == 'assistant']

if not assistant_msgs:
    print('Nenhuma resposta do assistente para analisar.')
else:
    print(f'Total de mensagens: {len(msgs)} ({len(assistant_msgs)} respostas do assistente)')
    print()
    
    for i, m in enumerate(assistant_msgs):
        content = m.get('content', '')
        print(f'--- Resposta #{i+1} ({len(content)} chars) ---')
        print(content[:500])
        if len(content) > 500:
            print('...')
        print()
" 2>/dev/null

  echo ""
  echo -e "${YELLOW}─── Para análise detalhada ───${NC}"
  echo ""
  echo "System Prompt do agente:"
  echo -e "${MAGENTA}${SYSTEM_PROMPT}${NC}"
  echo ""
  echo -e "Fluxo esperado: ${GREEN}${FLUXO_ESPERADO}${NC}"
  echo ""
  echo -e "Para uma análise mais precisa, copie o histórico acima (ou o arquivo"
  echo -e "'${HISTORY_FILE}') e peça para o LLM analisar se o agente"
  echo "está seguindo as regras definidas."
  echo ""

  # Option to run analyze script with more depth
  echo -e "${YELLOW}Deseja uma análise automatizada básica? (s/N)${NC}"
  read -r DO_ANALYZE
  if [[ "$DO_ANALYZE" == "s" || "$DO_ANALYZE" == "S" ]]; then
    "${SCRIPT_DIR}/analyze-results.sh" "$API_KEY" "$AGENT_ID" "${CONVERSATION_ID:-}" "$HISTORY_FILE" "$FLUXO_ESPERADO"
  fi
}

# ─── Step 4: Start fresh ─────────────────────────────────────────
start_new_conversation

# ─── Step 5: Main loop ──────────────────────────────────────────
while true; do
  echo -e "${BLUE}══════════════════════════════════════${NC}"
  echo -e "Conversation ID: ${GREEN}${CONVERSATION_ID:-"(nova conversa será criada)"}${NC}"
  echo -e "${BLUE}══════════════════════════════════════${NC}"
  echo ""
  echo -e "${YELLOW}Envie sua mensagem para o agente (ou diga 'sair', 'novo', 'histórico', 'analisar'):${NC}"
  read -r -p "Você: " USER_MSG

  # Handle meta-commands
  case "$USER_MSG" in
    sair|exit|quit|q)
      echo ""
      echo -e "${GREEN}Teste finalizado.${NC}"
      echo "Histórico salvo em: ${HISTORY_FILE}"
      echo "Conversation ID: ${CONVERSATION_ID:-"(nenhuma)"}"
      echo ""
      # Ask if wants to analyze before exiting
      echo -e "${YELLOW}Deseja analisar os resultados antes de sair? (s/N)${NC}"
      read -r DO_ANALYZE
      if [[ "$DO_ANALYZE" == "s" || "$DO_ANALYZE" == "S" ]]; then
        analyze_results
      fi
      echo ""
      echo "Bye!"
      exit 0
      ;;

    novo|new|reset|reiniciar)
      echo ""
      echo -e "${YELLOW}Iniciar nova conversa? A atual será descartada.${NC}"
      read -r -p "Confirma? (s/N): " CONFIRM
      if [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]]; then
        start_new_conversation
      fi
      continue
      ;;

    histórico|history|hist|h)
      show_history
      continue
      ;;

    analisar|analise|analyze|a)
      analyze_results
      continue
      ;;

    ajuda|help|?)
      echo ""
      echo -e "${YELLOW}Comandos disponíveis:${NC}"
      echo "  <mensagem>     - Envia a mensagem para o agente"
      echo "  sair           - Finaliza o teste"
      echo "  novo           - Inicia uma nova conversa (descarta a atual)"
      echo "  histórico      - Mostra o histórico da conversa atual"
      echo "  analisar       - Analisa as respostas contra o fluxo esperado"
      echo ""
      continue
      ;;

    "")
      continue
      ;;
  esac

  # Send query
  echo ""
  echo -e "${CYAN}─── Enviando mensagem ───${NC}"
  send_query "$USER_MSG"

  # Post-response menu
  while true; do
    echo -e "${BLUE}─── Ações ───${NC}"
    echo -e "  ${YELLOW}1${NC}) Continuar teste (enviar outra mensagem)"
    echo -e "  ${YELLOW}2${NC}) Ver histórico da conversa"
    echo -e "  ${YELLOW}3${NC}) Iniciar ${GREEN}NOVA${NC} conversa (descarta atual)"
    echo -e "  ${YELLOW}4${NC}) Analisar resultados até agora"
    echo -e "  ${YELLOW}5${NC}) Sair"
    echo ""
    read -r -p "Escolha: " ACTION

    case "$ACTION" in
      1) break ;;  # Go back to message loop
      2) show_history ; echo "" ;;
      3)
        echo ""
        read -r -p "Confirmar nova conversa? (s/N): " CONFIRM
        if [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]]; then
          start_new_conversation
          break 2  # Break out of action menu AND message loop, restart from top
        fi
        ;;
      4) analyze_results ;;
      5)
        echo ""
        echo -e "${GREEN}Teste finalizado.${NC}"
        echo "Histórico salvo em: ${HISTORY_FILE}"
        echo "Conversation ID: ${CONVERSATION_ID:-"(nenhuma)"}"
        echo ""
        exit 0
        ;;
      *) echo -e "${RED}Opção inválida${NC}" ;;
    esac
    echo ""
  done

done
