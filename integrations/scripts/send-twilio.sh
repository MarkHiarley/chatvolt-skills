#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-twilio
#
# ENVIO REAL de SMS via integração Twilio. Exige --yes explícito.
# A mensagem vai para o telefone do destinatário e fica registrada na
# conversa do contato — nunca rode isso contra números de clientes.
#
# Uso:
#   send-twilio.sh [api-key] --owner-phone <numero> --contact-phone <numero> \
#                  (--message <texto> | --json '<json>') --yes
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           equivale a --yes (automação)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-twilio.sh — envia um SMS via integração Twilio (ENVIO REAL)

Uso:
  send-twilio.sh [api-key] --owner-phone <numero> --contact-phone <numero> \
                 (--message <texto> | --json '<json>') --yes

Obrigatórios:
  --owner-phone <numero>    número Twilio remetente (verificado na conta) — path ownerPhone
  --contact-phone <numero>  destinatário (DDI+DDD, sem "+" nem espaços) — path contactPhone
  --message <texto>         texto do SMS (também pode vir dentro do --json)
  --yes                     confirma o ENVIO REAL (sem ele o script recusa)

Opcionais:
  --json '<json>'           objeto JSON mesclado no corpo (ex.: {"message":"ola"})
  -h, --help                mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY   API key (alternativa ao 1º argumento)
  CV_JSON=1          imprime somente JSON em stdout
  CV_YES=1           equivale a --yes
  CV_API_BASE        base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota/premium (402) · 4 rede · 5 servidor · 130 cancelado

Contrato: POST /twilio/{ownerPhone}/{contactPhone}/message  body {"message":"..."}
A resposta é o objeto Message criado no sistema ({id,text,conversationId,...}).
EOF
}

source "$(dirname "$0")/_lib.sh"

cv_path_arg() { # <nome> <valor> — path params não podem ser vazios nem conter "/" ou espaço
  case "$2" in
    ""|*/*|*" "*) cv_die "$1 inválido: '${2:-}' (não pode ser vazio nem conter '/' ou espaços)" ;;
  esac
  printf '%s' "$2"
}

API_KEY_ARG=""
# 1º argumento posicional = api-key (vence o CHATVOLT_API_KEY do ambiente).
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

OWNER_PHONE=""
CONTACT_PHONE=""
MESSAGE=""
EXTRA=""
ASSUME_YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --owner-phone)   [ "$#" -ge 2 ] || cv_die "--owner-phone exige um valor"; OWNER_PHONE="$2"; shift 2 ;;
    --contact-phone) [ "$#" -ge 2 ] || cv_die "--contact-phone exige um valor"; CONTACT_PHONE="$2"; shift 2 ;;
    --message)       [ "$#" -ge 2 ] || cv_die "--message exige um valor"; MESSAGE="$2"; shift 2 ;;
    --json)          [ "$#" -ge 2 ] || cv_die "--json exige um valor"; EXTRA="$2"; shift 2 ;;
    --yes)           ASSUME_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              cv_die "opção desconhecida: $1 (use --help)" ;;
    *)               cv_die "argumento extra: $1 (a mensagem vai em --message)" ;;
  esac
done

[ -n "$OWNER_PHONE" ]   || { usage >&2; cv_die "informe --owner-phone (número Twilio remetente)"; }
[ -n "$CONTACT_PHONE" ] || { usage >&2; cv_die "informe --contact-phone (destinatário)"; }
OWNER_PHONE=$(cv_path_arg "--owner-phone" "$OWNER_PHONE")
CONTACT_PHONE=$(cv_path_arg "--contact-phone" "$CONTACT_PHONE")

case "$OWNER_PHONE" in *[!0-9]*)   cv_warn "--owner-phone '$OWNER_PHONE' não é só dígitos — a Twilio espera DDI+DDD sem '+' nem espaços";; esac
case "$CONTACT_PHONE" in *[!0-9]*) cv_warn "--contact-phone '$CONTACT_PHONE' não é só dígitos — a API espera DDI+DDD sem '+' nem espaços";; esac

if [ "$ASSUME_YES" != "1" ] && [ "${CV_YES:-0}" != "1" ]; then
  cv_die "envio real de SMS para ${CONTACT_PHONE} exige --yes explícito (ou CV_YES=1 em automação); nada foi enviado"
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$MESSAGE" "$EXTRA" <<'PY'
import json, sys
message, extra = sys.argv[1], sys.argv[2]
body = {}
if extra:
    try:
        body = json.loads(extra)
    except Exception as exc:
        sys.stderr.write("--json inválido: %s\n" % exc); sys.exit(2)
    if not isinstance(body, dict):
        sys.stderr.write("--json precisa ser um objeto JSON\n"); sys.exit(2)
if message:
    body["message"] = message
if not str(body.get("message") or "").strip():
    sys.stderr.write("informe --message (ou --json com o campo \"message\")\n"); sys.exit(2)
print(json.dumps(body, ensure_ascii=False))
PY
) || cv_die "corpo da requisição inválido (veja a mensagem acima)"

cv_warn "ENVIO REAL: SMS via Twilio de ${OWNER_PHONE} para ${CONTACT_PHONE}."
cv_warn "A mensagem vai para o telefone do destinatário e é registrada na conversa do contato; não há como desfazer."
cv_info "Enviando SMS via Twilio (ownerPhone=${OWNER_PHONE}, contactPhone=${CONTACT_PHONE})…"

cv_request POST "/twilio/${OWNER_PHONE}/${CONTACT_PHONE}/message" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia")
    raise SystemExit
if not isinstance(d, dict) or not d:
    print("Resposta inesperada: " + raw.strip()[:200])
    raise SystemExit
print("Mensagem registrada como " + str(d.get("id", "?")) + " (canal Twilio/SMS).")
for label, key in (("conversa", "conversationId"), ("remetente", "from"), ("id externo", "externalId"), ("criada em", "createdAt")):
    v = d.get(key)
    if v not in (None, ""):
        print(label + ": " + str(v))
if d.get("text"):
    print("texto: " + str(d["text"]).replace("\n", " ")[:160])
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
