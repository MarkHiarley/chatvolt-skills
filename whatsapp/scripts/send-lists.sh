#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-lists
#
# Envia uma mensagem interativa com lista de opções / menu
# (POST /messages/interactive/send-lists).
#
# ATENÇÃO: esta rota ENVIA MENSAGEM REAL no WhatsApp (Z-API/Zapper) do contato.
#
# Uso:
#   send-lists.sh [api-key] --conversation <conversationId> --body <texto>
#                 --button-text <texto> [--agent <agentId>] [--header <texto>]
#                 [--footer <texto>] [--list-title <texto>] [--json '<extra>'] --yes
#
# Ambiente:
#   CHATVOLT_API_KEY / CHATVOLT_AGENT_ID   alternativas aos argumentos
#   CV_JSON=1    imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1     equivale a --yes
#   CV_API_BASE  sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-lists.sh — mensagem interativa com lista de opções (envio REAL)

Uso:
  send-lists.sh [api-key] --conversation <conversationId> --body <texto>
                --button-text <texto> [--agent <agentId>] [--header <texto>]
                [--footer <texto>] [--list-title <texto>] [--json '<extra>'] --yes

Campos obrigatórios do contrato (POST /messages/interactive/send-lists):
  agentId, conversationId, body_text, button_text

Opções:
  --conversation <id>    (obrigatório) id da conversa (conversationId)
  --body <texto>         (obrigatório) corpo da mensagem (body_text, máx. 4096)
  --button-text <texto>  (obrigatório) texto do botão que abre a lista (máx. 20)
  --agent <id>           agentId responsável (ou CHATVOLT_AGENT_ID)
  --header <texto>       cabeçalho opcional (header_text, máx. 60)
  --footer <texto>       rodapé opcional (footer_text, máx. 60)
  --list-title <texto>   título da lista (list_title; usado principalmente em Z-API)
  --json '<extra>'       objeto JSON com campos adicionais aceitos pela rota
  -y, --yes              confirma o ENVIO REAL (obrigatório)
  -h, --help             mostra esta ajuda

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
HEADER=""
FOOTER=""
LIST_TITLE=""
EXTRA=""
YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent) AGENT_ID_ARG="${2:-}"; shift 2 ;;
    --conversation) CONVERSATION_ID="${2:-}"; shift 2 ;;
    --body) BODY="${2:-}"; shift 2 ;;
    --button-text) BUTTON_TEXT="${2:-}"; shift 2 ;;
    --header) HEADER="${2:-}"; shift 2 ;;
    --footer) FOOTER="${2:-}"; shift 2 ;;
    --list-title) LIST_TITLE="${2:-}"; shift 2 ;;
    --json) EXTRA="${2:-}"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --) shift; break ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *) usage >&2; cv_die "argumento inesperado: $1" ;;
  esac
done

cv_chars() { python3 -c 'import sys; print(len(sys.argv[1]))' "$1"; }

# ── Validação de campos (contrato do openapi.yaml) ───────────────────────
AGENT_ID="${AGENT_ID_ARG:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$CONVERSATION_ID" ] || { usage >&2; cv_die "--conversation <conversationId> é obrigatório (contrato: conversationId)"; }
[ -n "$BODY" ] || { usage >&2; cv_die "--body <texto> é obrigatório (contrato: body_text)"; }
[ -n "$BUTTON_TEXT" ] || { usage >&2; cv_die "--button-text <texto> é obrigatório (contrato: button_text)"; }
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "--agent <agentId> é obrigatório (contrato: agentId; ou exporte CHATVOLT_AGENT_ID)"; }
[ "$(cv_chars "$BODY")" -le 4096 ] || cv_die "--body excede o máximo do contrato: 4096 caracteres"
[ "$(cv_chars "$BUTTON_TEXT")" -le 20 ] || cv_die "--button-text excede o máximo do contrato: 20 caracteres"
[ -z "$HEADER" ] || [ "$(cv_chars "$HEADER")" -le 60 ] || cv_die "--header excede o máximo do contrato: 60 caracteres"
[ -z "$FOOTER" ] || [ "$(cv_chars "$FOOTER")" -le 60 ] || cv_die "--footer excede o máximo do contrato: 60 caracteres"
if [ -n "$EXTRA" ]; then
  printf '%s' "$EXTRA" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if isinstance(d, dict) else 1)' || cv_die "--json precisa ser um objeto JSON válido"
fi

# ── Confirmação de ENVIO REAL ────────────────────────────────────────────
if [ "$YES" != "1" ] && [ "${CV_YES:-0}" != "1" ]; then
  cv_die "recusado: esta rota ENVIA uma mensagem real no WhatsApp do contato da conversa ${CONVERSATION_ID}. Rode com --yes para confirmar (ou CV_YES=1)."
fi
cv_warn "ENVIO REAL: a lista interativa será entregue no WhatsApp do contato da conversa ${CONVERSATION_ID}."

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$AGENT_ID" "$CONVERSATION_ID" "$BODY" "$BUTTON_TEXT" "$HEADER" "$FOOTER" "$LIST_TITLE" "$EXTRA" <<'PY'
import json, sys
agent, conv, body, button_text, header, footer, list_title, extra = sys.argv[1:9]
p = {"agentId": agent, "conversationId": conv, "body_text": body, "button_text": button_text}
if header:
    p["header_text"] = header
if footer:
    p["footer_text"] = footer
if list_title:
    p["list_title"] = list_title
if extra:
    p.update(json.loads(extra))
print(json.dumps(p, ensure_ascii=False))
PY
) || cv_die "não consegui montar o payload da lista"

cv_request POST "/messages/interactive/send-lists" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("Lista interativa enviada.")
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
