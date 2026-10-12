#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Investigation: mensagens de uma conversa (somente leitura).
# Uso: get-messages.sh <api-key> <conversation-id> [count]
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: get-messages.sh <api-key> <conversation-id> [count]

Busca as últimas <count> mensagens de uma conversa
(GET /conversation/{id}/messages/{count}) e imprime metadados + transcrição
com a origem de cada mensagem (from: human | agent). Somente leitura.

Argumentos:
  <api-key>          API key do Chatvolt (ou use CHATVOLT_API_KEY)
  <conversation-id>  ID da conversa
  [count]            quantas mensagens trazer, inteiro >= 1 (padrão: 50)

Opções:
  -h, --help         mostra esta ajuda

Exemplos:
  get-messages.sh "$CHATVOLT_API_KEY" cmv2rijx90buivfpf2lc479h2 100
  CV_JSON=1 get-messages.sh "" cmv2rijx90buivfpf2lc479h2 | jq '.messages | length'

Variáveis:
  CV_API_BASE   base URL alternativa (padrão https://api.chatvolt.ai)
  CV_JSON=1     imprime somente JSON em stdout (diagnósticos em stderr)

Resposta da API: {status, isAiEnabled, userId, organizationId,
                  participantsContacts, lastHumanInteractionAt, messages[]}

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
CONVERSATION_ID="${2:-${CHATVOLT_CONVERSATION_ID:-}}"
[ -n "$CONVERSATION_ID" ] || cv_die "informe o ID da conversa como 2o argumento ou exporte CHATVOLT_CONVERSATION_ID"

COUNT="${3:-50}"
case "$COUNT" in
  ''|*[!0-9]*) cv_die "count precisa ser um inteiro >= 1 (recebido: '$COUNT')" ;;
esac
[ "$COUNT" -ge 1 ] || cv_die "count precisa ser >= 1 (recebido: '$COUNT')"

cv_get "/conversation/${CONVERSATION_ID}/messages/${COUNT}"
PAYLOAD=$(cv_unwrap "$CV_RESP")

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$PAYLOAD"
else
  printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print("Resposta inesperada (esperado objeto):")
    print(json.dumps(d, indent=2, ensure_ascii=False))
    raise SystemExit(0)
msgs = d.get("messages") or []
uid = d.get("userId")
print("Conversa:        %s" % (sys.argv[1] if len(sys.argv) > 1 else ""))
print("Status:          %s" % d.get("status", ""))
print("IA ativa:        %s" % ("sim" if d.get("isAiEnabled") else "nao"))
print("userId:          %s" % (uid if uid else "(nenhum)"))
print("organizationId:  %s" % d.get("organizationId", ""))
print("Mensagens:       %d" % len(msgs))
print("=" * 60)
for m in msgs:
    text = (m.get("text") or "").strip()
    if not text:
        continue
    src = m.get("from", "system")
    if src == "agent":
        label = "AGENT"
    elif src == "human":
        label = "HUMAN"
    else:
        label = src.upper()
    print("[%s] %s" % (label, m.get("createdAt", "")))
    print(text)
    print("-" * 60)
' "$CONVERSATION_ID"
fi
