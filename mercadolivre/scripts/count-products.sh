#!/usr/bin/env bash
set -euo pipefail

# chatvolt-mercadolivre — count-products.sh
# Conta os produtos do Mercado Livre sincronizados (GET /mercadolivre/products/count).
#
# Verificado ao vivo em 2026-10-12:
#   - sem agentId  → {"count":54721}  (total da organização/provedor global)
#   - com agentId  → {"count":0}      (escopo do agente)

usage() {
  cat <<'EOF'
Uso: count-products.sh <api-key> [agent-id] [opções]

Conta os produtos do Mercado Livre sincronizados no Chatvolt.

Sem o agent-id a API devolve o total da organização; com o agent-id devolve o
total daquele agente.

Opções:
  --agent <id>   id do agente (alternativa ao 2º argumento).
  -h, --help     esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_JSON=1           imprime SOMENTE JSON em stdout ({"count":N})
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Resposta da API: {"count":N}

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplos:
  count-products.sh "$KEY"
  count-products.sh "$KEY" "$AG"
  count-products.sh "$KEY" --agent "$AG"
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
[ "$#" -ge 1 ] && shift

AGENT_ID=""
if [ "$#" -ge 1 ] && [ "${1#-}" = "$1" ]; then AGENT_ID="$1"; shift; fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)   [ -n "${2:-}" ] || cv_die "--agent exige um valor"; AGENT_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

AGENT_ID="${AGENT_ID:-${CHATVOLT_AGENT_ID:-}}"

if [ -n "$AGENT_ID" ]; then
  cv_get "/mercadolivre/products/count" --get --data-urlencode "agentId=${AGENT_ID}"
else
  cv_get "/mercadolivre/products/count"
fi

ROOT=$(cv_unwrap "$CV_RESP")
COUNT=$(printf '%s' "$ROOT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    v = d.get("count")
elif isinstance(d, (int, float)):
    v = d
else:
    v = None
print("" if v is None else int(v))
')

[ -n "$COUNT" ] || cv_die "resposta sem o campo 'count': $(printf '%s' "$ROOT" | head -c 300)"

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$ROOT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
d = d if isinstance(d, dict) else {"count": d}
print(json.dumps(d, ensure_ascii=False))
'
  exit 0
fi

if [ -n "$AGENT_ID" ]; then
  cv_info "Total de produtos do Mercado Livre (agente ${AGENT_ID}): ${COUNT}"
else
  cv_info "Total de produtos do Mercado Livre (organização, sem filtro de agente): ${COUNT}"
fi
