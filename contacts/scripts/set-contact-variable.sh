#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — set-contact-variable
#
# Cria ou atualiza uma variável customizada de contato.
#   POST /contacts/variables → create/update (upsert atômico em JSONB)
#   PUT  /contacts/variables → atualização (funcionalmente idêntico ao POST)
#
# O corpo exige `key`, `value` e `source`; `id` é o contato (ou a conversa, cujo
# primeiro participante é resolvido). `value` aceita qualquer tipo JSON.
# Chaves começando com `_` são reservadas (não use).
#
# Uso:
#   set-contact-variable.sh [api-key] <contact-id> --key <chave> (--value <texto> | --value-json <json>) [--source human|ai] [--update]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
set-contact-variable.sh — cria/atualiza uma variável de contato (POST|PUT /contacts/variables)

Uso:
  set-contact-variable.sh [api-key] <contact-id> --key <chave> (--value <texto> | --value-json <json>) [opções]

Argumentos:
  <contact-id>        id do contato (ou da conversa) — obrigatório

Opções:
  --key <chave>       nome da variável (obrigatório; não pode começar com "_")
  --value <texto>     valor como string
  --value-json <json> valor já em JSON (número, booleano, objeto, array, null)
  --source <origem>   human (padrão) ou ai
  --update            usa PUT em vez de POST (mesmo comportamento de upsert)
  -h, --help          mostra esta ajuda

Exemplos:
  set-contact-variable.sh "$CHATVOLT_API_KEY" contact_abc123 --key plano --value pro
  set-contact-variable.sh "$CHATVOLT_API_KEY" contact_abc123 --key pedidos --value-json '[1,2,3]' --source ai

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
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then CONTACT_ID="$1"; shift; fi

KEY=""
VALUE=""
VALUE_SET=0
VALUE_JSON=""
VALUE_JSON_SET=0
SOURCE="human"
UPDATE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --key)        KEY="${2:?--key exige o nome da variável}"; shift 2 ;;
    --value)      VALUE="${2:?--value exige um valor}"; VALUE_SET=1; shift 2 ;;
    --value-json) VALUE_JSON="${2:?--value-json exige um JSON}"; VALUE_JSON_SET=1; shift 2 ;;
    --source)     SOURCE="${2:?--source exige human ou ai}"; shift 2 ;;
    --update)     UPDATE=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

[ -n "$CONTACT_ID" ] || cv_die "informe o id do contato (ou da conversa): set-contact-variable.sh [api-key] <id> --key <chave> --value <valor>"
[ -n "$KEY" ] || cv_die "informe --key <chave>"
case "$KEY" in _*) cv_die "--key não pode começar com '_' (prefixo reservado pela API)" ;; esac
[ "$VALUE_SET" = "1" ] || [ "$VALUE_JSON_SET" = "1" ] || cv_die "informe --value <texto> ou --value-json <json>"
if [ "$VALUE_SET" = "1" ] && [ "$VALUE_JSON_SET" = "1" ]; then
  cv_die "use apenas um entre --value e --value-json"
fi
case "$SOURCE" in human|ai) ;; *) cv_die "--source inválido: $SOURCE (use human ou ai)" ;; esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

if ! BODY=$(python3 - "$CONTACT_ID" "$KEY" "$VALUE" "$VALUE_JSON" "$SOURCE" "$VALUE_JSON_SET" <<'PY'
import json, sys
cid, key, value, value_json, source, json_set = sys.argv[1:7]
if json_set == "1":
    try:
        val = json.loads(value_json)
    except Exception:
        print("--value-json não é um JSON válido", file=sys.stderr); raise SystemExit(1)
else:
    val = value
print(json.dumps({"id": cid, "key": key, "value": val, "source": source}, ensure_ascii=False))
PY
); then
  cv_die "payload inválido (veja a mensagem acima)"
fi

METHOD="POST"
if [ "$UPDATE" = "1" ]; then METHOD="PUT"; fi

cv_request "$METHOD" "/contacts/variables" "$BODY"

NORM=$(printf '%s' "$(cv_unwrap "$CV_RESP")" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    d = {}
print(json.dumps({"variables": d.get("variables") or {}}, ensure_ascii=False))
')

cv_info "Variável '${KEY}' definida no contato ${CONTACT_ID} (${METHOD})."
cv_emit "$NORM" "import json,sys
d=json.load(sys.stdin)
print(json.dumps(d.get('variables') or {}, indent=2, ensure_ascii=False))"
