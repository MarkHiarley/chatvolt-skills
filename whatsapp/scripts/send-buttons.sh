#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-buttons
#
# Envia uma mensagem interativa com até 3 botões de resposta
# (POST /messages/interactive/send-buttons).
#
# ATENÇÃO: esta rota ENVIA MENSAGEM REAL no WhatsApp (Z-API/Zapper) do contato.
#
# Uso:
#   send-buttons.sh [api-key] --conversation <conversationId> --body <texto>
#                   --button <id>=<titulo> [--button ...]... [--agent <agentId>]
#                   [--header <texto>] [--footer <texto>] --yes
#
# Ambiente:
#   CHATVOLT_API_KEY / CHATVOLT_AGENT_ID   alternativas aos argumentos
#   CV_JSON=1    imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1     equivale a --yes
#   CV_API_BASE  sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-buttons.sh — mensagem interativa com botões de resposta (envio REAL)

Uso:
  send-buttons.sh [api-key] --conversation <conversationId> --body <texto>
                  --button <id>=<titulo> [--button ...]... [--agent <agentId>]
                  [--header <texto>] [--footer <texto>] --yes

Campos obrigatórios do contrato (POST /messages/interactive/send-buttons):
  agentId, conversationId, body_text, button_1_id, button_1_title
  (até 3 botões: button_2_id/button_2_title, button_3_id/button_3_title)

Opções:
  --conversation <id>   (obrigatório) id da conversa (conversationId)
  --body <texto>        (obrigatório) corpo da mensagem (body_text)
  --button <id>=<titulo> (obrigatório, 1 a 3) botão de resposta rápida. Repetível.
  --agent <id>          agentId responsável (ou CHATVOLT_AGENT_ID)
  --header <texto>      cabeçalho opcional (header_text)
  --footer <texto>      rodapé opcional (footer_text)
  -y, --yes             confirma o ENVIO REAL (obrigatório)
  -h, --help            mostra esta ajuda

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
HEADER=""
FOOTER=""
YES=0
BUTTONS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent) AGENT_ID_ARG="${2:-}"; shift 2 ;;
    --conversation) CONVERSATION_ID="${2:-}"; shift 2 ;;
    --body) BODY="${2:-}"; shift 2 ;;
    --header) HEADER="${2:-}"; shift 2 ;;
    --footer) FOOTER="${2:-}"; shift 2 ;;
    --button) BUTTONS+=("${2:-}"); shift 2 ;;
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
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "--agent <agentId> é obrigatório (contrato: agentId; ou exporte CHATVOLT_AGENT_ID)"; }
[ "${#BUTTONS[@]}" -ge 1 ] || { usage >&2; cv_die "informe ao menos um --button <id>=<titulo> (contrato: button_1_id/button_1_title)"; }
[ "${#BUTTONS[@]}" -le 3 ] || cv_die "máximo de 3 botões (contrato: button_1_*, button_2_*, button_3_*)"

# ── Confirmação de ENVIO REAL ────────────────────────────────────────────
if [ "$YES" != "1" ] && [ "${CV_YES:-0}" != "1" ]; then
  cv_die "recusado: esta rota ENVIA uma mensagem real no WhatsApp do contato da conversa ${CONVERSATION_ID}. Rode com --yes para confirmar (ou CV_YES=1)."
fi
cv_warn "ENVIO REAL: a mensagem de botões será entregue no WhatsApp do contato da conversa ${CONVERSATION_ID}."

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$AGENT_ID" "$CONVERSATION_ID" "$BODY" "$HEADER" "$FOOTER" ${BUTTONS[@]+"${BUTTONS[@]}"} <<'PY'
import json, sys
agent, conv, body, header, footer = sys.argv[1:6]
buttons = sys.argv[6:]
p = {"agentId": agent, "conversationId": conv, "body_text": body}
if header:
    p["header_text"] = header
if footer:
    p["footer_text"] = footer
seen = set()
for i, raw in enumerate(buttons, 1):
    bid, sep, title = raw.partition("=")
    if not sep or not bid or not title:
        print("--button inválido: " + raw + " (use id=título, ex.: sim=Sim)", file=sys.stderr)
        raise SystemExit(1)
    if bid in seen:
        print("--button com id repetido: " + bid, file=sys.stderr)
        raise SystemExit(1)
    seen.add(bid)
    p["button_%d_id" % i] = bid
    p["button_%d_title" % i] = title
print(json.dumps(p, ensure_ascii=False))
PY
) || cv_die "não consegui montar o payload dos botões"

cv_request POST "/messages/interactive/send-buttons" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("Mensagem de botões enviada.")
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
