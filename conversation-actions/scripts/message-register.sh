#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — message-register
#
# Registra uma mensagem/evento no contexto da conversa SEM enviá-la ao cliente.
# Serve para deixar rastro de ações de sistemas externos (CRM, ERP, e-mail).
#
# Uso:
#   message-register.sh [api-key] <conversation-id> --message "<texto>" [--from human|agent]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
message-register.sh — registra uma mensagem na conversa sem enviá-la ao cliente

Uso:
  message-register.sh [api-key] <conversation-id> --message "<texto>" [--from human|agent]

Argumentos:
  <conversation-id>  id da conversa

Opções:
  --message "<texto>"  conteúdo a registrar no contexto (obrigatório)
  --from <quem>        human (padrão) ou agent — quem "assinou" o registro
  -h, --help           mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY     API key (alternativa ao 1º argumento)
  CV_JSON=1            imprime somente JSON em stdout
  CV_API_BASE          base URL alternativa (default https://api.chatvolt.ai)

Endpoint: POST /conversations/{conversationId}/message-register {message, from}
A mensagem NÃO é entregue ao participante: ela só entra no histórico/contexto
da conversa. Para enviar de verdade use send-message.sh (exige --yes).

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
MESSAGE=""
FROM="human"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --message) [ -n "${2:-}" ] || cv_die "--message exige o texto"; MESSAGE="$2"; shift 2 ;;
    --from)    [ -n "${2:-}" ] || cv_die "--from exige human ou agent"; FROM="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }
[ -n "$MESSAGE" ] || { usage >&2; cv_die "informe --message \"<texto>\""; }

case "$FROM" in
  human|agent) ;;
  *) cv_die "--from inválido: '$FROM' — use human ou agent" ;;
esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

BODY=$(python3 - "$MESSAGE" "$FROM" <<'PY'
import json, sys
print(json.dumps({"message": sys.argv[1], "from": sys.argv[2]}, ensure_ascii=False))
PY
)

cv_warn "registro interno: a mensagem entra no contexto da conversa ${CONV_ID} e NÃO é enviada ao cliente"

cv_request POST "/conversations/${CONV_ID}/message-register" "$BODY"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    msg = d.get("message")
    if isinstance(msg, dict):
        print("OK: mensagem registrada (id %s)" % msg.get("id", "?"))
    else:
        print("OK:", msg or d.get("success"))
else:
    print(d)'
