#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-message
#
# AVISO: ENVIA UMA MENSAGEM REAL para o cliente (WhatsApp, Telegram, webchat...).
# Exige --yes explicitamente e nunca deve ser usado em teste automatizado.
#
# Uso:
#   send-message.sh [api-key] (--conversation-id <id> | --phone <numero> | --email <e>)
#                   --message "<texto>" [--agent-id <id>] [--channel <canal>]
#                   [--visitor-id <id>] [--contact-id <id>]
#                   [--attachment-url <url> [--attachment-name <nome>] [--attachment-mime <mime>]]
#                   --yes
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-message.sh — ENVIA uma mensagem real em uma conversa do Chatvolt

AVISO: ATENÇÃO: este script entrega uma mensagem de verdade ao cliente final.
    Ele exige --yes e NÃO é usado em testes (a rota é validada só no stub).

Uso:
  send-message.sh [api-key] (--conversation-id <id> | --phone <numero> | --email <e>)
                  --message "<texto>" [--agent-id <id>] [--channel <canal>]
                  [--visitor-id <id>] [--contact-id <id>]
                  [--attachment-url <url> [--attachment-name <nome>] [--attachment-mime <mime>]]
                  --yes

Destinatário (informe exatamente um):
  --conversation-id <id>  envia pela conversa existente (type=conversationId)
  --phone <numero>        envia pelo telefone (type=phone) — exige --agent-id ou --channel
  --email <e>             envia pelo e-mail (type=email) — exige --agent-id ou --channel

Opções:
  --message "<texto>"     conteúdo da mensagem (obrigatório, máx. 1 MB no payload)
  --agent-id <id>         id do agente que assina o envio (formato cuid)
  --channel <canal>       website | dashboard | whatsapp | zapi | telegram | instagramDm
  --visitor-id <id>       id do visitante, se aplicável
  --contact-id <id>       id do contato, se aplicável
  --attachment-url <url>  anexo: URL pública
  --attachment-name <n>   anexo: nome exibido
  --attachment-mime <m>   anexo: MIME type (ex. application/pdf)
  --yes                   confirma que você quer enviar a mensagem ao cliente (obrigatório)
  -h, --help              mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY        API key (alternativa ao 1º argumento)
  CV_JSON=1               imprime somente JSON em stdout
  CV_API_BASE             base URL alternativa (default https://api.chatvolt.ai)

Endpoint: POST /conversation/message/{type}/{value} {message, agentId?, channel?, ...}

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
PHONE=""
EMAIL=""
MESSAGE=""
AGENT_ID=""
CHANNEL=""
VISITOR_ID=""
CONTACT_ID=""
ATT_URL=""
ATT_NAME=""
ATT_MIME=""
YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --conversation-id) [ -n "${2:-}" ] || cv_die "--conversation-id exige um valor"; CONV_ID="$2"; shift 2 ;;
    --phone)           [ -n "${2:-}" ] || cv_die "--phone exige um valor"; PHONE="$2"; shift 2 ;;
    --email)           [ -n "${2:-}" ] || cv_die "--email exige um valor"; EMAIL="$2"; shift 2 ;;
    --message)         [ -n "${2:-}" ] || cv_die "--message exige o texto"; MESSAGE="$2"; shift 2 ;;
    --agent-id)        [ -n "${2:-}" ] || cv_die "--agent-id exige um valor"; AGENT_ID="$2"; shift 2 ;;
    --channel)         [ -n "${2:-}" ] || cv_die "--channel exige um valor"; CHANNEL="$2"; shift 2 ;;
    --visitor-id)      [ -n "${2:-}" ] || cv_die "--visitor-id exige um valor"; VISITOR_ID="$2"; shift 2 ;;
    --contact-id)      [ -n "${2:-}" ] || cv_die "--contact-id exige um valor"; CONTACT_ID="$2"; shift 2 ;;
    --attachment-url)  [ -n "${2:-}" ] || cv_die "--attachment-url exige uma URL"; ATT_URL="$2"; shift 2 ;;
    --attachment-name) [ -n "${2:-}" ] || cv_die "--attachment-name exige um valor"; ATT_NAME="$2"; shift 2 ;;
    --attachment-mime) [ -n "${2:-}" ] || cv_die "--attachment-mime exige um valor"; ATT_MIME="$2"; shift 2 ;;
    --yes)             YES=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    -*)                cv_die "opção desconhecida: $1 (use --help)" ;;
    *)                 cv_die "argumento extra: $1 (o destinatário é informado por --conversation-id/--phone/--email)" ;;
  esac
done

[ -n "$CONV_ID$PHONE$EMAIL" ] || { usage >&2; cv_die "informe o destinatário: --conversation-id, --phone ou --email"; }

TARGETS=0
for v in "$CONV_ID" "$PHONE" "$EMAIL"; do
  [ -n "$v" ] && TARGETS=$((TARGETS + 1))
done
[ "$TARGETS" -eq 1 ] || cv_die "informe apenas um destinatário (--conversation-id, --phone ou --email)"

[ -n "$MESSAGE" ] || { usage >&2; cv_die "informe --message \"<texto>\""; }

if [ -n "$CONV_ID" ]; then
  TYPE="conversationId"; VALUE="$CONV_ID"
elif [ -n "$PHONE" ]; then
  TYPE="phone"; VALUE="$PHONE"
else
  TYPE="email"; VALUE="$EMAIL"
fi

if [ "$TYPE" != "conversationId" ] && [ -z "$AGENT_ID$CHANNEL" ]; then
  cv_die "com --phone/--email a API exige --agent-id ou --channel (sem eles responde 400 INVALID_REQUEST)"
fi

case "$CHANNEL" in
  ""|website|dashboard|whatsapp|zapi|telegram|instagramDm) ;;
  *) cv_die "--channel inválido: '$CHANNEL' — use website, dashboard, whatsapp, zapi, telegram ou instagramDm" ;;
esac

[ -z "$ATT_URL" ] && { [ -z "$ATT_NAME$ATT_MIME" ] || cv_die "--attachment-name/--attachment-mime exigem --attachment-url"; }

if [ "$YES" != "1" ]; then
  cv_die "esta chamada ENVIA uma mensagem REAL para o cliente final (rota POST /conversation/message/${TYPE}/${VALUE}). Se é isso mesmo que você quer, repita o comando com --yes. Em teste automatizado, use o stub — nunca um contato real."
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

cv_warn "ATENÇÃO: enviando uma mensagem REAL via ${TYPE}=${VALUE} (canal: ${CHANNEL:-automático do destinatário})"
cv_warn "mensagem: ${MESSAGE}"

BODY=$(python3 - "$MESSAGE" "$AGENT_ID" "$CHANNEL" "$VISITOR_ID" "$CONTACT_ID" "$ATT_URL" "$ATT_NAME" "$ATT_MIME" <<'PY'
import json, sys
message, agent_id, channel, visitor_id, contact_id, att_url, att_name, att_mime = sys.argv[1:9]
b = {"message": message}
if agent_id:
    b["agentId"] = agent_id
if channel:
    b["channel"] = channel
if visitor_id:
    b["visitorId"] = visitor_id
if contact_id:
    b["contactId"] = contact_id
if att_url:
    att = {"url": att_url}
    if att_name:
        att["name"] = att_name
    if att_mime:
        att["mimeType"] = att_mime
    b["attachments"] = [att]
print(json.dumps(b, ensure_ascii=False))
PY
)

cv_request POST "/conversation/message/${TYPE}/${VALUE}" "$BODY"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    msg = d.get("message")
    if isinstance(msg, dict):
        print("OK: mensagem enviada (id %s)" % msg.get("id", "?"))
    else:
        print("OK:", msg or d.get("success"))
else:
    print(d)'
