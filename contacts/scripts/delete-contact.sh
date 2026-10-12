#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — delete-contact
#
# Remove um contato (DELETE /contacts/{id}). Antes de apagar, tenta buscar os
# dados do contato para mostrar o que será removido.
#
# IMPORTANTE: NÃO existe `GET /contacts/{id}` na API (só o DELETE nesse path,
# verificado ao vivo em 2026-10-12). A busca prévia é feita com
# `GET /contacts?search=<termo>` filtrando o id localmente. Se o contato não
# aparecer na busca, o script avisa e segue para a confirmação.
#
# Uso:
#   delete-contact.sh [api-key] <contact-id> [--search <termo>]
#
# Opções:
#   --search <termo>   e-mail/telefone/nome usado na busca prévia (padrão: o id)
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_YES=1           pula a confirmação (automação)
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)

usage() {
  cat <<'EOF'
delete-contact.sh — deleta um contato do Chatvolt (DELETE /contacts/{id})

Uso:
  delete-contact.sh [api-key] <contact-id> [--search <termo>]

Argumentos:
  <contact-id>       id do contato a deletar (obrigatório)

Opções:
  --search <termo>   e-mail, telefone ou nome para a busca prévia
                     (padrão: o próprio id; não existe GET /contacts/{id})
  -h, --help         mostra esta ajuda

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
SEARCH=""

if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then CONTACT_ID="$1"; shift; fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --search) SEARCH="${2:?--search exige um termo}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

[ -n "$CONTACT_ID" ] || cv_die "informe o id do contato: delete-contact.sh [api-key] <contact-id> [--search <termo>]"

API_KEY=$(cv_req_key "$API_KEY_ARG")

# ── busca prévia (a API não tem GET /contacts/{id}) ────────────────────────
TERM="${SEARCH:-$CONTACT_ID}"
FOUND=""
cv_get "/contacts" --get --data-urlencode "search=${TERM}" --data-urlencode "limit=20"
FOUND=$(printf '%s' "$(cv_unwrap "$CV_RESP")" | python3 -c '
import json, sys
d = json.load(sys.stdin)
items = d.get("contacts") if isinstance(d, dict) else d
for c in items or []:
    if c.get("id") == sys.argv[1]:
        print(json.dumps(c, ensure_ascii=False)); break
' "$CONTACT_ID")

if [ -n "$FOUND" ]; then
  cv_info "Contato encontrado na busca por '${TERM}':"
  cv_emit "$FOUND" "import json,sys
c=json.load(sys.stdin)
n=' '.join(x for x in (c.get('firstName'), c.get('lastName')) if x) or '-'
print(f\"  id={c.get('id')}  nome={n}  email={c.get('email') or '-'}  telefone={c.get('phoneNumber') or '-'}\")"
else
  cv_warn "não encontrei os dados do contato ${CONTACT_ID} buscando por '${TERM}' (GET /contacts/{id} não existe); seguindo só com o id"
fi

cv_confirm "Deletar DEFINITIVAMENTE o contato ${CONTACT_ID}? Esta ação não pode ser desfeita."

cv_request DELETE "/contacts/${CONTACT_ID}" ""
cv_emit "$(cv_unwrap "$CV_RESP")" "import json,sys
d=json.load(sys.stdin)
print(d.get('message') if isinstance(d,dict) and d.get('message') else f'Contato {json.dumps(d, ensure_ascii=False)} removido.')"
