#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — create-contact
#
# Cria (sem `--id`) ou atualiza (com `--id`) um contato via POST /contacts.
# O contrato real usa os campos `email`, `phoneNumber`, `firstName`, `lastName`,
# `externalId`, `picture` e `metadata` (ContactPayload do openapi). A doc
# narrativa cita `name`/`phone` — a API ignora esses campos; não use.
#
# Uso:
#   create-contact.sh [api-key] [opções]
#
# Opções:
#   --id <contact-id>      atualiza o contato existente (update) em vez de criar
#   --email <email>
#   --phone <telefone>     telefone com DDI, sem "+" (ex.: 5511988887777)
#   --first-name <nome>
#   --last-name <sobrenome>
#   --user-id <id-ext>     identificador externo → campo `externalId`
#   --picture <url>
#   --metadata '<json>'    objeto JSON livre → campo `metadata`
#   --json '<json>'        objeto JSON extra mesclado no payload
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
create-contact.sh — cria ou atualiza um contato do Chatvolt (POST /contacts)

Uso:
  create-contact.sh [api-key] [opções]

Opções:
  --id <contact-id>      atualiza o contato existente (update) em vez de criar
  --email <email>
  --phone <telefone>     telefone com DDI, sem "+" (ex.: 5511988887777)
  --first-name <nome>
  --last-name <sobrenome>
  --user-id <id-ext>     identificador externo (campo externalId)
  --picture <url>
  --metadata '<json>'    objeto JSON livre (campo metadata)
  --json '<json>'        objeto JSON extra mesclado no payload
  -h, --help             mostra esta ajuda

Exemplos:
  create-contact.sh "$CHATVOLT_API_KEY" --email cliente@exemplo.com --first-name Ana
  create-contact.sh "$CHATVOLT_API_KEY" --phone 5511988887777 --user-id US.123
  create-contact.sh "$CHATVOLT_API_KEY" --id contact_abc123 --last-name Souza

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONTACT_ID=""
EMAIL=""
PHONE=""
FIRST_NAME=""
LAST_NAME=""
USER_ID=""
PICTURE=""
METADATA=""
EXTRA=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --id)         CONTACT_ID="${2:?--id exige um id de contato}"; shift 2 ;;
    --email)      EMAIL="${2:?--email exige um valor}"; shift 2 ;;
    --phone)      PHONE="${2:?--phone exige um telefone com DDI}"; shift 2 ;;
    --first-name) FIRST_NAME="${2:?--first-name exige um valor}"; shift 2 ;;
    --last-name)  LAST_NAME="${2:?--last-name exige um valor}"; shift 2 ;;
    --user-id)    USER_ID="${2:?--user-id exige um identificador externo}"; shift 2 ;;
    --picture)    PICTURE="${2:?--picture exige uma URL}"; shift 2 ;;
    --metadata)   METADATA="${2:?--metadata exige um objeto JSON}"; shift 2 ;;
    --json)       EXTRA="${2:?--json exige um objeto JSON}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

if [ -n "$EMAIL" ]; then
  case "$EMAIL" in *@*.*) ;; *) cv_die "--email inválido: $EMAIL" ;; esac
fi
if [ -n "$PHONE" ]; then
  case "$PHONE" in *[!0-9]*) cv_die "--phone deve conter apenas dígitos (DDI + número, ex.: 5511988887777)" ;; esac
fi
if [ -z "$EMAIL" ] && [ -z "$PHONE" ] && [ -z "$USER_ID" ] && [ -z "$FIRST_NAME" ] \
   && [ -z "$LAST_NAME" ] && [ -z "$PICTURE" ] && [ -z "$METADATA" ] && [ -z "$EXTRA" ]; then
  cv_die "informe ao menos --email, --phone ou --user-id (ou algum campo a gravar)"
fi

if ! BODY=$(python3 - "$CONTACT_ID" "$EMAIL" "$PHONE" "$FIRST_NAME" "$LAST_NAME" "$USER_ID" "$PICTURE" "$METADATA" "$EXTRA" <<'PY'
import json, sys
cid, email, phone, first, last, userid, picture, metadata, extra = sys.argv[1:10]
p = {}
if cid:      p["id"] = cid
if email:    p["email"] = email
if phone:    p["phoneNumber"] = phone
if first:    p["firstName"] = first
if last:     p["lastName"] = last
if userid:   p["externalId"] = userid
if picture:  p["picture"] = picture
if metadata:
    try:
        md = json.loads(metadata)
    except Exception:
        print("--metadata não é um JSON válido", file=sys.stderr); raise SystemExit(1)
    if not isinstance(md, dict):
        print("--metadata deve ser um objeto JSON", file=sys.stderr); raise SystemExit(1)
    p["metadata"] = md
if extra:
    try:
        ex = json.loads(extra)
    except Exception:
        print("--json não é um JSON válido", file=sys.stderr); raise SystemExit(1)
    if not isinstance(ex, dict):
        print("--json deve ser um objeto JSON", file=sys.stderr); raise SystemExit(1)
    p.update(ex)
print(json.dumps(p, ensure_ascii=False))
PY
); then
  cv_die "payload inválido (veja a mensagem acima)"
fi

cv_request POST "/contacts" "$BODY"

# Aceita as duas formas de resposta: contato na raiz ou envelope {data,success}.
CONTACT=$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "success" in d:
    d = d["data"]
elif isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
print(json.dumps(d, ensure_ascii=False))
')

read -r -d '' FORMATTER <<'PY' || true
import json, sys
c = json.load(sys.stdin)
if not isinstance(c, dict) or not c:
    print(json.dumps(c, indent=2, ensure_ascii=False)); raise SystemExit
name = " ".join(x for x in (c.get("firstName"), c.get("lastName")) if x) or "-"
print(f"Contato {'atualizado' if c.get('updatedAt') else 'salvo'}: {c.get('id')}")
print(f"  Nome:     {name}")
print(f"  E-mail:   {c.get('email') or '-'}")
print(f"  Telefone: {c.get('phoneNumber') or '-'}")
print(f"  Criado:   {c.get('createdAt') or '-'}")
PY

cv_emit "$CONTACT" "$FORMATTER"
