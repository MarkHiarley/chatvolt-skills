#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Investigation: envia uma query de teste ao agente.
# Uso: test-query.sh <api-key> <agent-id> <query> [temperature] [model]
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: test-query.sh <api-key> <agent-id> <query> [temperature] [model]

Envia uma pergunta ao agente (POST /agents/{id}/query, sem streaming) e
imprime a resposta, o conversationId criado e o lembrete de como apagar a
conversa de teste. Cria uma conversa real no histórico do agente.

Argumentos:
  <api-key>      API key do Chatvolt (ou use CHATVOLT_API_KEY)
  <agent-id>     ID do agente (ou use CHATVOLT_AGENT_ID)
  <query>        pergunta a enviar
  [temperature]  0.0 a 1.0 (opcional; sobrescreve a do agente nesta chamada)
  [model]        nome do modelo (opcional; sobrescreve o do agente)

Opções:
  -h, --help     mostra esta ajuda

Exemplos:
  test-query.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1 "Qual o prazo de entrega?"
  test-query.sh "" cmt8mfhzv00h2g9gtypyp54l1 "Repita sem citar preço" 0.2

Resposta da API: {answer, sources, messageId, conversationId, visitorId}
Limpeza: conversation-cleanup/scripts/delete-conversation.sh <api-key> <conversationId>

Variáveis:
  CV_API_BASE   base URL alternativa (padrão https://api.chatvolt.ai)
  CV_JSON=1     imprime somente JSON em stdout (diagnósticos em stderr)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
AGENT_ID="${2:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o ID do agente como 2o argumento ou exporte CHATVOLT_AGENT_ID"
QUERY="${3:-}"
[ -n "$QUERY" ] || cv_die "informe a pergunta como 3o argumento"
TEMPERATURE="${4:-}"
MODEL="${5:-}"

if [ -n "$TEMPERATURE" ]; then
  case "$TEMPERATURE" in
    *[!0-9.]*|*.*.*|.*|*.) cv_die "temperatura inválida: '$TEMPERATURE' (use 0.0 a 1.0)" ;;
  esac
  awk -v t="$TEMPERATURE" 'BEGIN { exit !(t >= 0 && t <= 1) }' \
    || cv_die "temperatura fora da faixa 0.0 a 1.0 (recebido: '$TEMPERATURE')"
fi

BODY=$(python3 - "$QUERY" "$TEMPERATURE" "$MODEL" <<'PY'
import json, sys
query, temperature, model = sys.argv[1], sys.argv[2], sys.argv[3]
body = {"query": query, "streaming": False}
if temperature:
    body["temperature"] = float(temperature)
if model:
    body["modelName"] = model
print(json.dumps(body, ensure_ascii=False))
PY
)

cv_info "Enviando query ao agente ${AGENT_ID}..." >&2
cv_request POST "/agents/${AGENT_ID}/query" "$BODY"
PAYLOAD=$(cv_unwrap "$CV_RESP")

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$PAYLOAD"
else
  printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print(json.dumps(d, indent=2, ensure_ascii=False))
    raise SystemExit(0)
conv = d.get("conversationId", "")
print("Resposta:")
print(d.get("answer", "(vazia)"))
print()
print("conversationId: %s" % conv)
print("messageId:      %s" % d.get("messageId", ""))
print("visitorId:      %s" % d.get("visitorId", ""))
src = d.get("sources") or []
print("fontes usadas:  %d" % (len(src) if isinstance(src, list) else 0))
print()
print("Esta chamada criou uma conversa real no histórico do agente.")
print("Para apagá-la:")
print("  conversation-cleanup/scripts/delete-conversation.sh <api-key> %s" % (conv or "<conversationId>"))
'
fi
