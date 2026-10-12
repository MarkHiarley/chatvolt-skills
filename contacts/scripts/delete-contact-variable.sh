#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — delete-contact-variable
#
# Remove variáveis de um contato (DELETE /contacts/variables?id=…[&key=…]):
#   --key <chave>    remove apenas essa variável (404 se a chave não existir)
#   --all-variables  remove o registro inteiro de variáveis do contato
#
# Uso:
#   delete-contact-variable.sh [api-key] <contact-id> (--key <chave> | --all-variables)
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_YES=1           pula a confirmação (automação)
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)

usage() {
  cat <<'EOF'
delete-contact-variable.sh — remove variáveis de um contato (DELETE /contacts/variables)

Uso:
  delete-contact-variable.sh [api-key] <contact-id> (--key <chave> | --all-variables)

Argumentos:
  <contact-id>        id do contato (ou da conversa) — obrigatório

Opções:
  --key <chave>       remove apenas esta variável
  --all-variables     remove TODAS as variáveis do contato (sem --key)
  -h, --help          mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_YES=1            pula a confirmação
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
ALL_VARS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --key)           KEY="${2:?--key exige o nome da variável}"; shift 2 ;;
    --all-variables) ALL_VARS=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

[ -n "$CONTACT_ID" ] || cv_die "informe o id do contato (ou da conversa): delete-contact-variable.sh [api-key] <id> --key <chave>"
if [ -z "$KEY" ] && [ "$ALL_VARS" != "1" ]; then
  cv_die "informe --key <chave> (ou --all-variables para apagar todas as variáveis do contato)"
fi
if [ -n "$KEY" ] && [ "$ALL_VARS" = "1" ]; then
  cv_die "use --key OU --all-variables, não os dois"
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

if [ -n "$KEY" ]; then
  cv_confirm "Remover a variável '${KEY}' do contato ${CONTACT_ID}?"
else
  cv_confirm "Remover TODAS as variáveis do contato ${CONTACT_ID}?"
fi

if [ -n "$KEY" ]; then
  cv_request DELETE "/contacts/variables" "" --get --data-urlencode "id=${CONTACT_ID}" --data-urlencode "key=${KEY}"
else
  cv_request DELETE "/contacts/variables" "" --get --data-urlencode "id=${CONTACT_ID}"
fi

NORM=$(printf '%s' "$(cv_unwrap "$CV_RESP")" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    d = {}
print(json.dumps({"variables": d.get("variables") or {}}, ensure_ascii=False))
')

if [ -n "$KEY" ]; then
  cv_info "Variável '${KEY}' removida do contato ${CONTACT_ID}."
else
  cv_info "Todas as variáveis do contato ${CONTACT_ID} foram removidas."
fi
cv_emit "$NORM" "import json,sys
d=json.load(sys.stdin)
v=d.get('variables') or {}
print(json.dumps(v, indent=2, ensure_ascii=False) if v else 'Sem variáveis restantes.')"
