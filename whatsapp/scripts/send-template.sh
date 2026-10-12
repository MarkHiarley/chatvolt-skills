#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-template
#
# Envia um template APROVADO do WhatsApp (POST /whatsapp/{phoneNumberId}/template-message).
# É o caminho obrigatório para a PRIMEIRA mensagem a um contato.
#
# ATENÇÃO: esta rota ENVIA MENSAGEM REAL no WhatsApp do destinatário.
#
# Uso:
#   send-template.sh [api-key] --phone-number <phoneNumberId> --to <numero> --text <texto>
#                    --template <nome> --lang <codigo> [--agent <agentId>]
#                    [--default-status <RESOLVED|UNRESOLVED|HUMAN_REQUESTED>]
#                    [--button <tipo>:<valor>:<index>]... [--var var_x=valor]... --yes
#
# Ambiente:
#   CHATVOLT_API_KEY / CHATVOLT_AGENT_ID   alternativas aos argumentos
#   CV_JSON=1    imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1     equivale a --yes
#   CV_API_BASE  sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-template.sh — envia um template aprovado do WhatsApp (envio REAL)

Uso:
  send-template.sh [api-key] --phone-number <phoneNumberId> --to <numero> --text <texto>
                   --template <nome> --lang <codigo> [--agent <agentId>]
                   [--default-status <RESOLVED|UNRESOLVED|HUMAN_REQUESTED>]
                   [--button <tipo>:<valor>:<index>]... [--var var_x=valor]... --yes

Campos obrigatórios do contrato (POST /whatsapp/{phoneNumberId}/template-message):
  to, text, agentId, templateName, templateLangCode

Opções:
  --phone-number <id>   (obrigatório) id do número WhatsApp Business (path param)
  --to <numero>         (obrigatório) telefone do destinatário com DDI, só dígitos
                        (ex.: 55987654321)
  --text <texto>        (obrigatório) texto gravado no histórico da conversa
                        (variáveis posicionais: {{1}}, {{2}})
  --template <nome>     (obrigatório) nome do template aprovado (templateName)
  --lang <codigo>       (obrigatório) idioma do template (templateLangCode, ex.: pt_BR)
  --agent <id>          agentId associado à mensagem (ou CHATVOLT_AGENT_ID)
  --default-status <s>  RESOLVED | UNRESOLVED | HUMAN_REQUESTED
  --button <t>:<v>:<i>  botão dinâmico: tipo (url|quick_reply|copy_code|flow|catalog),
                        valor e índice. Repetível.
  --var <var_x>=<valor> variável dinâmica do template (prefixo var_ obrigatório)
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
PHONE_NUMBER_ID=""
TO=""
TEXT=""
TEMPLATE=""
LANG=""
DEFAULT_STATUS=""
YES=0
BTNS=()
VARS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --phone-number) PHONE_NUMBER_ID="${2:-}"; shift 2 ;;
    --to) TO="${2:-}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    --template) TEMPLATE="${2:-}"; shift 2 ;;
    --lang) LANG="${2:-}"; shift 2 ;;
    --agent) AGENT_ID_ARG="${2:-}"; shift 2 ;;
    --default-status) DEFAULT_STATUS="${2:-}"; shift 2 ;;
    --button) BTNS+=("${2:-}"); shift 2 ;;
    --var) VARS+=("${2:-}"); shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --) shift; break ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *) usage >&2; cv_die "argumento inesperado: $1" ;;
  esac
done

# ── Validação de campos (contrato do openapi.yaml) ───────────────────────
AGENT_ID="${AGENT_ID_ARG:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$PHONE_NUMBER_ID" ] || { usage >&2; cv_die "--phone-number <phoneNumberId> é obrigatório (path param da rota)"; }
[ -n "$TO" ] || { usage >&2; cv_die "--to <numero> é obrigatório (contrato: to)"; }
[ -n "$TEXT" ] || { usage >&2; cv_die "--text <texto> é obrigatório (contrato: text)"; }
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "--agent <agentId> é obrigatório (contrato: agentId; ou exporte CHATVOLT_AGENT_ID)"; }
[ -n "$TEMPLATE" ] || { usage >&2; cv_die "--template <nome> é obrigatório (contrato: templateName)"; }
[ -n "$LANG" ] || { usage >&2; cv_die "--lang <codigo> é obrigatório (contrato: templateLangCode; ex.: pt_BR)"; }

[[ "$TO" =~ ^[0-9]{8,15}$ ]] || cv_die "--to inválido: use só dígitos com DDI, sem '+' nem espaços (ex.: 55987654321)"

if [ -n "$DEFAULT_STATUS" ]; then
  case "$DEFAULT_STATUS" in
    RESOLVED|UNRESOLVED|HUMAN_REQUESTED) ;;
    *) cv_die "--default-status inválido: ${DEFAULT_STATUS} (use RESOLVED, UNRESOLVED ou HUMAN_REQUESTED)" ;;
  esac
fi

if [ "${#VARS[@]}" -gt 0 ]; then
  for v in "${VARS[@]}"; do
    key="${v%%=*}"
    [[ "$key" =~ ^var_[a-zA-Z_][a-zA-Z0-9_]*$ ]] || cv_die "--var inválida: '${key}' (o contrato exige o prefixo var_ seguido de letras/números/_, ex.: var_customer_name)"
    [ "$key" != "$v" ] || cv_die "--var inválida: '${v}' (use var_nome=valor)"
  done
fi

# ── Confirmação de ENVIO REAL ────────────────────────────────────────────
if [ "$YES" != "1" ] && [ "${CV_YES:-0}" != "1" ]; then
  cv_die "recusado: esta rota ENVIA uma mensagem real no WhatsApp de ${TO}. Rode com --yes para confirmar (ou CV_YES=1)."
fi
cv_warn "ENVIO REAL: o template '${TEMPLATE}' (${LANG}) será entregue no WhatsApp de ${TO}."

API_KEY=$(cv_req_key "$API_KEY_ARG")

ARGS=()
for b in "${BTNS[@]}"; do ARGS+=("button:${b}"); done
for v in "${VARS[@]}"; do ARGS+=("var:${v}"); done

PAYLOAD=$(python3 - "$TO" "$TEXT" "$AGENT_ID" "$TEMPLATE" "$LANG" "$DEFAULT_STATUS" ${ARGS[@]+"${ARGS[@]}"} <<'PY'
import json, sys
to, text, agent, tpl, lang, default_status = sys.argv[1:7]
extra = sys.argv[7:]
BTN_TYPES = {"url", "quick_reply", "copy_code", "flow", "catalog"}
p = {"to": to, "text": text, "agentId": agent, "templateName": tpl, "templateLangCode": lang}
if default_status:
    p["defaultStatus"] = default_status
buttons = []
for item in extra:
    kind, _, value = item.partition(":")
    if kind == "button":
        parts = value.split(":", 2)
        if len(parts) != 3 or not all(parts):
            print("--button inválido: use <tipo>:<valor>:<index> (ex.: url:promo2024:0)", file=sys.stderr)
            raise SystemExit(1)
        btype, bvalue, bindex = parts
        if btype not in BTN_TYPES:
            print("--button tipo inválido: " + btype + " (use " + ", ".join(sorted(BTN_TYPES)) + ")", file=sys.stderr)
            raise SystemExit(1)
        buttons.append({"type": btype, "value": bvalue, "index": bindex})
    elif kind == "var":
        key, sep, val = value.partition("=")
        if not sep:
            print("--var inválida: " + value + " (use var_nome=valor)", file=sys.stderr)
            raise SystemExit(1)
        p[key] = val
    else:
        print("argumento interno inesperado: " + item, file=sys.stderr)
        raise SystemExit(1)
if buttons:
    p["buttons"] = buttons
print(json.dumps(p, ensure_ascii=False))
PY
) || cv_die "não consegui montar o payload do template"

cv_request POST "/whatsapp/${PHONE_NUMBER_ID}/template-message" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("Template enviado.")
    print("  conversa:    " + str(d.get("id") or "-"))
    print("  canal:       " + str(d.get("channel") or "-"))
    print("  id externo:  " + str(d.get("channelExternalId") or "-"))
    print("  mensagens:   " + str(len(d.get("messages") or [])))
else:
    print(json.dumps(d, ensure_ascii=False))
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
