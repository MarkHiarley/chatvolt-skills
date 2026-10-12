#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-cta
#
# Envia uma mensagem interativa com botão de URL / call to action
# (POST /messages/interactive/send-cta).
#
# ATENÇÃO: esta rota ENVIA MENSAGEM REAL no WhatsApp (Z-API) do contato.
#
# Uso:
#   send-cta.sh [api-key] --conversation <conversationId> --body <texto>
#               --button-text <texto> --url <https://...> [--agent <agentId>]
#               [--header <texto>] [--footer <texto>] --yes
#
# Ambiente:
#   CHATVOLT_API_KEY / CHATVOLT_AGENT_ID   alternativas aos argumentos
#   CV_JSON=1    imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1     equivale a --yes
#   CV_API_BASE  sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-cta.sh — mensagem interativa com botão de URL (envio REAL)

Uso:
  send-cta.sh [api-key] --conversation <conversationId> --body <texto>
              --button-text <texto> --url <https://...> [--agent <agentId>]
              [--header <texto>] [--footer <texto>] --yes

Campos obrigatórios do contrato (POST /messages/interactive/send-cta):
  agentId, conversationId, body_text, button_display_text, button_url

Opções:
  --conversation <id>     (obrigatório) id da conversa (conversationId)
  --body <texto>          (obrigatório) corpo da mensagem (body_text)
  --button-text <texto>   (obrigatório) rótulo do botão (button_display_text)
  --url <url>             (obrigatório) URL do CTA, http/https (button_url)
  --agent <id>            agentId responsável (ou CHATVOLT_AGENT_ID)
  --header <texto>        cabeçalho opcional (header_text)
  --footer <texto>        rodapé opcional (footer_text)
  -y, --yes               confirma o ENVIO REAL (obrigatório)
  -h, --help              mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   agentId (alternativa ao --agent)
  CV_JSON=1           imprime somente JSON em stdout
  CV_YES=1            equivale a --yes
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

AGENT_ID_ARG=""
CONVERSATION_ID=""
BODY=""
BUTTON_TEXT=""
URL=""
HEADER=""
FOOTER=""
YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent) AGENT_ID_ARG="${2:-}"; shift 2 ;;
    --conversation) CONVERSATION_ID="${2:-}"; shift 2 ;;
    --body) BODY="${2:-}"; shift 2 ;;
    --button-text) BUTTON_TEXT="${2:-}"; shift 2 ;;
    --url) URL="${2:-}"; shift 2 ;;
    --header) HEADER="${2:-}"; shift 2 ;;
    --footer) FOOTER="${2:-}"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --) shift; break ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *) usage >&2; cv_die "argumento inesperado: $1" ;;
  esac
done

# ── Validação de campos (contrato do openapi.yaml) ───────────────────────
AGENT_ID="${AGENT_ID_ARG:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$CONVERSATION_ID" ] || { usage >&2; cv_die "--conversation <conversationId> é obrigatório (contrato: conversationId)"; }
[ -n "$BODY" ] || { usage >&2; cv_die "--body <texto> é obrigatório (contrato: body_text)"; }
[ -n "$BUTTON_TEXT" ] || { usage >&2; cv_die "--button-text <texto> é obrigatório (contrato: button_display_text)"; }
[ -n "$URL" ] || { usage >&2; cv_die "--url <url> é obrigatório (contrato: button_url)"; }
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "--agent <agentId> é obrigatório (contrato: agentId; ou exporte CHATVOLT_AGENT_ID)"; }

python3 - "$URL" <<'PY' || cv_die "--url inválida: use uma URL absoluta http:// ou https:// (contrato: button_url format url)"
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
ok = u.scheme in ("http", "https") and bool(u.netloc)
raise SystemExit(0 if ok else 1)
PY

# ── Confirmação de ENVIO REAL ────────────────────────────────────────────
if [ "$YES" != "1" ] && [ "${CV_YES:-0}" != "1" ]; then
  cv_die "recusado: esta rota ENVIA uma mensagem real no WhatsApp do contato da conversa ${CONVERSATION_ID}. Rode com --yes para confirmar (ou CV_YES=1)."
fi
cv_warn "ENVIO REAL: o CTA com a URL ${URL} será entregue no WhatsApp do contato da conversa ${CONVERSATION_ID}."

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$AGENT_ID" "$CONVERSATION_ID" "$BODY" "$BUTTON_TEXT" "$URL" "$HEADER" "$FOOTER" <<'PY'
import json, sys
agent, conv, body, button_text, url, header, footer = sys.argv[1:8]
p = {"agentId": agent, "conversationId": conv, "body_text": body,
     "button_display_text": button_text, "button_url": url}
if header:
    p["header_text"] = header
if footer:
    p["footer_text"] = footer
print(json.dumps(p, ensure_ascii=False))
PY
) || cv_die "não consegui montar o payload do CTA"

cv_request POST "/messages/interactive/send-cta" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("CTA enviado.")
    if d.get("messageId"):
        print("  id:     " + str(d["messageId"]))
    if d.get("status"):
        print("  status: " + str(d["status"]))
    if not d.get("messageId") and not d.get("status"):
        print(json.dumps(d, ensure_ascii=False))
else:
    print(json.dumps(d, ensure_ascii=False))
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
