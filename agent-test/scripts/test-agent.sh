#!/usr/bin/env bash
set -euo pipefail

# test-agent.sh — sessão interativa de teste de um agente Chatvolt.
#
# Fluxo: config do agente → fluxo esperado → conversa nova → loop pergunta/resposta
# Ações: continuar · nova conversa · histórico · analisar · sair
# Reutiliza get-agent.sh, send-query.sh e analyze-results.sh (mesma pasta).

source "$(dirname "$0")/_lib.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<'EOF'
Uso: test-agent.sh <api-key> <agent-id>
     test-agent.sh <agent-id>          (com CHATVOLT_API_KEY no ambiente)

Sessão interativa para testar um agente:
  1. mostra a configuração atual (nome, modelo, temperatura, system prompt, tools);
  2. pergunta quais regras o agente deve seguir (fluxo esperado);
  3. a primeira pergunta abre uma conversa NOVA (nada é escrito em conversas reais);
  4. loop de perguntas com comandos:

     :c, :continuar     envia a próxima pergunta na mesma conversa (padrão:
                        qualquer texto sem ':' é uma pergunta)
     :n, :nova          descarta a conversa atual; a próxima pergunta abre outra
     :h, :historico     imprime a transcrição da conversa atual (via API)
     :a, :analisar      roda analyze-results.sh com as regras desta sessão
     :s, :sair          encerra a sessão (mostra o conversationId para limpeza)
     :help, :ajuda      mostra esta ajuda

Nenhum arquivo temporário é criado: a transcrição vem sempre da API.

Variáveis: CHATVOLT_API_KEY · CV_API_BASE

Exemplo:
  test-agent.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

if [ -n "${CHATVOLT_API_KEY:-}" ] && [ $# -le 1 ]; then
  AGENT_ID="${1:-}"
  API_KEY=$(cv_req_key)
else
  API_KEY=$(cv_req_key "${1:-}")
  AGENT_ID="${2:-}"
fi
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "informe o agent-id"; }

CONVERSATION_ID=""
RULES=""

show_history() {
  if [ -z "$CONVERSATION_ID" ]; then
    cv_warn "nenhuma conversa iniciada ainda nesta sessão"
    return 0
  fi
  cv_get "/conversation/${CONVERSATION_ID}/messages/200"
  printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
msgs = list(reversed((d or {}).get("messages") or []))
print("Histórico da conversa (%d mensagens)" % len(msgs))
for i, m in enumerate(msgs, 1):
    autor = str(m.get("from", "?")).lower()
    rotulo = {"human": "HUMAN", "agent": "AGENT", "user": "HUMAN", "bot": "AGENT"}.get(autor, autor.upper())
    texto = m.get("text")
    if texto is None:
        texto = m.get("content") or "(sem texto)"
    print("[%d] %s" % (i, rotulo))
    for linha in str(texto).splitlines() or [""]:
        print("    " + linha)
'
}

run_analysis() {
  if [ -z "$CONVERSATION_ID" ]; then
    cv_warn "nenhuma conversa iniciada ainda nesta sessão"
    return 0
  fi
  if [ -n "$RULES" ]; then
    "$SCRIPT_DIR/analyze-results.sh" "$API_KEY" "$AGENT_ID" "$CONVERSATION_ID" --expected "$RULES"
  else
    "$SCRIPT_DIR/analyze-results.sh" "$API_KEY" "$AGENT_ID" "$CONVERSATION_ID"
  fi
}

ask() {
  local pergunta="$1"
  local args=( "$API_KEY" "$AGENT_ID" "$pergunta" )
  if [ -n "$CONVERSATION_ID" ]; then
    args+=( --conversation "$CONVERSATION_ID" --force )
  fi

  local out
  if ! out=$(CV_JSON=1 "$SCRIPT_DIR/send-query.sh" "${args[@]}"); then
    cv_warn "a query falhou; a sessão continua"
    return 0
  fi

  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print("(resposta inesperada da API)")
    raise SystemExit(0)
print("RESPOSTA")
print("-" * 60)
print(d.get("answer", "(sem resposta)"))
print("-" * 60)
print("conversationId: %s" % d.get("conversationId", "-"))
print("messageId:      %s" % d.get("messageId", "-"))
sources = d.get("sources") or []
print("sources:        %d" % len(sources))
for s in sources:
    nome = s.get("datasource_name") or s.get("datasource_id") or "?"
    try:
        score = format(float(s.get("score")), ".4f")
    except (TypeError, ValueError):
        score = str(s.get("score", "-"))
    print("  - %s  score=%s" % (nome, score))
'
  CONVERSATION_ID=$(printf '%s' "$out" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print((d or {}).get("conversationId", "") or "")')
}

# ─── 1. Configuração do agente ────────────────────────────────────────────────
printf '\n' >&2
"$SCRIPT_DIR/get-agent.sh" "$API_KEY" "$AGENT_ID"

# ─── 2. Fluxo esperado ───────────────────────────────────────────────────────
printf '\n' >&2
printf 'Fluxo esperado — regras que o agente deve seguir (uma por linha ou separadas por ";").\n' >&2
printf 'Enter para pular: ' >&2
IFS= read -r RULES || RULES=""

printf '\n' >&2
printf 'Sessão de teste iniciada. Digite a pergunta, ou :ajuda para ver os comandos.\n' >&2
printf 'A primeira pergunta abre uma conversa NOVA (nada é escrito em conversas reais).\n' >&2

# ─── 3. Loop ─────────────────────────────────────────────────────────────────
while :; do
  printf '\n> ' >&2
  line=""
  IFS= read -r line || break
  case "$line" in
    :s|:sair|sair|exit|quit|:q) break ;;
    :n|:nova|"nova conversa"|nova)
      CONVERSATION_ID=""
      cv_info "O.K. — a próxima pergunta abre uma nova conversa."
      continue ;;
    :h|:historico|historico|histórico|:hist)
      show_history
      continue ;;
    :a|:analisar|analisar|analise|análise)
      run_analysis
      continue ;;
    :help|:ajuda|ajuda|help)
      usage
      continue ;;
    "") continue ;;
  esac
  ask "$line"
done

printf '\n' >&2
if [ -n "$CONVERSATION_ID" ]; then
  cv_info "Sessão encerrada. Conversa de teste: ${CONVERSATION_ID}"
  cv_info "Para apagá-la: conversation-cleanup/scripts/delete-conversation.sh <api-key> ${CONVERSATION_ID}"
else
  cv_info "Sessão encerrada. Nenhuma conversa foi criada."
fi
