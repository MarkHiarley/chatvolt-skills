#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — list-contact-variables
#
# Lista as variáveis customizadas de um contato (GET /contacts/variables?id=…).
# O parâmetro `id` aceita um **id de contato** ou um **id de conversa** (o
# primeiro contato participante é resolvido automaticamente).
#
# Uso:
#   list-contact-variables.sh [api-key] <contact-id|conversation-id>
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
list-contact-variables.sh — lista as variáveis de um contato (GET /contacts/variables)

Uso:
  list-contact-variables.sh [api-key] <contact-id|conversation-id>

Argumentos:
  <contact-id|conversation-id>   id do contato (ou da conversa) — obrigatório

Resposta: {variables: {...}, variableList: [{varName, varValue, source}]}
  A chave especial `_sources` dentro de `variables` mapeia cada variável para
  sua origem (`human` ou `ai`).

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

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

[ -n "$CONTACT_ID" ] || cv_die "informe o id do contato (ou da conversa): list-contact-variables.sh [api-key] <id>"

API_KEY=$(cv_req_key "$API_KEY_ARG")

cv_get "/contacts/variables" --get --data-urlencode "id=${CONTACT_ID}"

NORM=$(printf '%s' "$(cv_unwrap "$CV_RESP")" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    d = {}
print(json.dumps({
    "variables": d.get("variables") or {},
    "variableList": d.get("variableList") or [],
}, ensure_ascii=False))
')

read -r -d '' FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
items = d.get("variableList") or []
if not items:
    print("Nenhuma variável customizada neste contato.")
    raise SystemExit
print(f"{'VARIÁVEL':28} {'ORIGEM':8} VALOR")
for v in items:
    name = str(v.get("varName", ""))
    src = str(v.get("source", ""))
    val = v.get("varValue")
    val = val if isinstance(val, str) else json.dumps(val, ensure_ascii=False)
    print(f"{name[:28]:28} {src[:8]:8} {val}")
print(f"\nTotal: {len(items)}")
PY

cv_emit "$NORM" "$FORMATTER"
