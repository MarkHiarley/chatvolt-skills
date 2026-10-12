#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-contact
#
# Envia um cartão de contato numa conversa
# (POST /messages/interactive/send-contact).
#
# ATENÇÃO: esta rota ENVIA MENSAGEM REAL no WhatsApp (Z-API/Zapper) do contato.
#
# Uso:
#   send-contact.sh [api-key] --conversation <conversationId> --name <nome exibido>
#                   [--agent <agentId>] [--json '<extra>'] --yes
#
# Ambiente:
#   CHATVOLT_API_KEY / CHATVOLT_AGENT_ID   alternativas aos argumentos
#   CV_JSON=1    imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1     equivale a --yes
#   CV_API_BASE  sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-contact.sh — envia um cartão de contato no WhatsApp (envio REAL)

Uso:
  send-contact.sh [api-key] --conversation <conversationId> --name <nome exibido>
                  [--agent <agentId>] [--json '<extra>'] --yes

Campos obrigatórios do contrato (POST /messages/interactive/send-contact):
  agentId, conversationId, name_formatted_name

Opções:
  --conversation <id>   (obrigatório) id da conversa (conversationId)
  --name <nome>         (obrigatório) nome exibido no cartão (name_formatted_name)
  --agent <id>          agentId responsável (ou CHATVOLT_AGENT_ID)
  --json '<extra>'      objeto JSON com campos extras que a rota aceita
                        (a rota tem additionalProperties: true; a página de
                        visão geral usa to/phone, mas o contrato exige
                        name_formatted_name)
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
CONTACT_NAME=""
EXTRA=""
YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent) AGENT_ID_ARG="${2:-}"; shift 2 ;;
    --conversation) CONVERSATION_ID="${2:-}"; shift 2 ;;
    --name) CONTACT_NAME="${2:-}"; shift 2 ;;
    --json) EXTRA="${2:-}"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --) shift; break ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *) usage >&2; cv_die "argumento inesperado: $1" ;;
  esac
done

# ── Validação de campos (contrato do openapi.yaml) ───────────────────────
AGENT_ID="${AGENT_ID_ARG:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$CONVERSATION_ID" ] || { usage >&2; cv_die "--conversation <conversationId> é obrigatório (contrato: conversationId)"; }
[ -n "$CONTACT_NAME" ] || { usage >&2; cv_die "--name <nome exibido> é obrigatório (contrato: name_formatted_name)"; }
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "--agent <agentId> é obrigatório (contrato: agentId; ou exporte CHATVOLT_AGENT_ID)"; }
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
cv_warn "ENVIO REAL: o cartão de contato '${CONTACT_NAME}' será entregue no WhatsApp do contato da conversa ${CONVERSATION_ID}."

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$AGENT_ID" "$CONVERSATION_ID" "$CONTACT_NAME" "$EXTRA" <<'PY'
import json, sys
agent, conv, name, extra = sys.argv[1:5]
p = {"agentId": agent, "conversationId": conv, "name_formatted_name": name}
if extra:
    p.update(json.loads(extra))
print(json.dumps(p, ensure_ascii=False))
PY
) || cv_die "não consegui montar o payload do contato"

cv_request POST "/messages/interactive/send-contact" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("Cartão de contato enviado.")
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
