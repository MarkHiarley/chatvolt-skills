#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-zapi
#
# ENVIO REAL de mensagem WhatsApp via integração Z-API. Exige --yes explícito.
# A mensagem vai para o WhatsApp do destinatário e fica registrada na conversa
# do contato — nunca rode isso contra números de clientes.
#
# Uso:
#   send-zapi.sh [api-key] --instance <id> --contact-phone <numero> \
#                (--message <texto> | --json '<json>') --yes
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           equivale a --yes (automação)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-zapi.sh — envia mensagem WhatsApp via integração Z-API (ENVIO REAL)

Uso:
  send-zapi.sh [api-key] --instance <id> --contact-phone <numero> \
               (--message <texto> | --json '<json>') --yes

Obrigatórios:
  --instance <id>           id da instância Z-API (externalId do ServiceProvider "zapi") — path instanceId
  --contact-phone <numero>  WhatsApp do destinatário (DDI+DDD, sem "+" nem espaços) — path contactPhone
  --message <texto>         texto da mensagem (também pode vir dentro do --json)
  --yes                     confirma o ENVIO REAL (sem ele o script recusa)

Opcionais:
  --json '<json>'           objeto JSON mesclado no corpo; usa-se para anexos, ex.:
                            --json '{"attachments":[{"url":"https://exemplo.com/foto.jpg","name":"foto.jpg","mimeType":"image/jpeg"}]}'
  -h, --help                mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY   API key (alternativa ao 1º argumento)
  CV_JSON=1          imprime somente JSON em stdout
  CV_YES=1           equivale a --yes
  CV_API_BASE        base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota/premium (402) · 4 rede · 5 servidor · 130 cancelado

Contrato: POST /zapi/{instanceId}/{contactPhone}/message
  body {"message":"...","attachments":[{"url","name?","mimeType?"}]}
O corpo exige message OU attachments; a resposta é o objeto Message criado.
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

INSTANCE=""
CONTACT_PHONE=""
MESSAGE=""
EXTRA=""
ASSUME_YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance)      [ "$#" -ge 2 ] || cv_die "--instance exige um valor"; INSTANCE="$2"; shift 2 ;;
    --contact-phone) [ "$#" -ge 2 ] || cv_die "--contact-phone exige um valor"; CONTACT_PHONE="$2"; shift 2 ;;
    --message)       [ "$#" -ge 2 ] || cv_die "--message exige um valor"; MESSAGE="$2"; shift 2 ;;
    --json)          [ "$#" -ge 2 ] || cv_die "--json exige um valor"; EXTRA="$2"; shift 2 ;;
    --yes)           ASSUME_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              cv_die "opção desconhecida: $1 (use --help)" ;;
    *)               cv_die "argumento extra: $1 (a mensagem vai em --message)" ;;
  esac
done

[ -n "$INSTANCE" ]      || { usage >&2; cv_die "informe --instance (id da instância Z-API)"; }
[ -n "$CONTACT_PHONE" ] || { usage >&2; cv_die "informe --contact-phone (destinatário)"; }
INSTANCE=$(cv_path_arg "--instance" "$INSTANCE")
CONTACT_PHONE=$(cv_path_arg "--contact-phone" "$CONTACT_PHONE")

case "$CONTACT_PHONE" in *[!0-9]*) cv_warn "--contact-phone '$CONTACT_PHONE' não é só dígitos — a API espera DDI+DDD sem '+' nem espaços";; esac

if [ "$ASSUME_YES" != "1" ] && [ "${CV_YES:-0}" != "1" ]; then
  cv_die "envio real de WhatsApp para ${CONTACT_PHONE} exige --yes explícito (ou CV_YES=1 em automação); nada foi enviado"
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
atts = body.get("attachments")
if atts is not None and not isinstance(atts, list):
    sys.stderr.write('"attachments" precisa ser uma lista\n'); sys.exit(2)
for i, att in enumerate(atts or []):
    if not isinstance(att, dict) or not att.get("url"):
        sys.stderr.write('attachments[%d] precisa de "url"\n' % i); sys.exit(2)
if not str(body.get("message") or "").strip() and not atts:
    sys.stderr.write('informe --message (ou --json com "message"/"attachments")\n'); sys.exit(2)
print(json.dumps(body, ensure_ascii=False))
PY
) || cv_die "corpo da requisição inválido (veja a mensagem acima)"

cv_warn "ENVIO REAL: WhatsApp via Z-API (instância ${INSTANCE}) para ${CONTACT_PHONE}."
cv_warn "A mensagem vai para o WhatsApp do destinatário e é registrada na conversa do contato; não há como desfazer."
cv_info "Enviando mensagem WhatsApp via Z-API (instanceId=${INSTANCE}, contactPhone=${CONTACT_PHONE})…"

cv_request POST "/zapi/${INSTANCE}/${CONTACT_PHONE}/message" "$PAYLOAD"

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
print("Mensagem registrada como " + str(d.get("id", "?")) + " (canal Z-API/WhatsApp).")
for label, key in (("conversa", "conversationId"), ("remetente", "from"), ("id externo", "externalId"), ("criada em", "createdAt")):
    v = d.get(key)
    if v not in (None, ""):
        print(label + ": " + str(v))
if d.get("text"):
    print("texto: " + str(d["text"]).replace("\n", " ")[:160])
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
