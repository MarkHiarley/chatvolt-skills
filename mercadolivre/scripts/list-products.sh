#!/usr/bin/env bash
set -euo pipefail

# chatvolt-mercadolivre — list-products.sh
# Lista os produtos do Mercado Livre sincronizados para um agente do Chatvolt.
#
# A rota GET /mercadolivre/products NÃO aceita faltar parâmetro: sem
# agentId + serviceProviderId a API responde
#   400 {"error":"agentId and serviceProviderId are required"}
# (verificado ao vivo em 2026-10-12).

usage() {
  cat <<'EOF'
Uso: list-products.sh <api-key> <agent-id> --service-provider <id> [opções]

Lista os produtos do Mercado Livre sincronizados no Chatvolt (tabela).

Opções:
  --service-provider <id>  (obrigatório) id do provedor do Mercado Livre.
               Sem ele a API responde 400 "agentId and serviceProviderId are
               required" — o parâmetro NÃO é documentado na doc pública.
  --agent <id>             id do agente (alternativa ao 2º argumento).
  --page <n>               página (default 1).
  --per-page <n>           itens por página (default 50; a API usa 8 quando
               o parâmetro é omitido e devolve o valor escolhido em "perPage").
  --all                    percorre as páginas até cobrir "total".
  --full                   imprime o JSON completo da resposta (não a tabela).
  -h, --help               esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_JSON=1           imprime SOMENTE JSON em stdout (array de produtos)
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Resposta da API: {"products":[…],"total":N,"page":P,"perPage":M}

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplos:
  list-products.sh "$KEY" "$AG" --service-provider sp-1
  list-products.sh "$KEY" "$AG" --service-provider sp-1 --per-page 20 --page 2
  CV_JSON=1 list-products.sh "$KEY" "$AG" --service-provider sp-1
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

SP_ID=""
PAGE=1
PER_PAGE=50
ALL=0
FULL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)            [ -n "${2:-}" ] || cv_die "--agent exige um valor"; AGENT_ID="$2"; shift 2 ;;
    --service-provider) [ -n "${2:-}" ] || cv_die "--service-provider exige um valor"; SP_ID="$2"; shift 2 ;;
    --page)             [ -n "${2:-}" ] || cv_die "--page exige um valor"; PAGE="$2"; shift 2 ;;
    --per-page)         [ -n "${2:-}" ] || cv_die "--per-page exige um valor"; PER_PAGE="$2"; shift 2 ;;
    --all)              ALL=1; shift ;;
    --full)             FULL=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

AGENT_ID="${AGENT_ID:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id como 2º argumento ou exporte CHATVOLT_AGENT_ID"
[ -n "$SP_ID" ]    || cv_die "--service-provider é obrigatório: /mercadolivre/products exige agentId + serviceProviderId (400 sem eles)"
[[ "$PAGE" =~ ^[1-9][0-9]*$ ]]     || cv_die "--page exige um inteiro >= 1 (recebido: $PAGE)"
[[ "$PER_PAGE" =~ ^[1-9][0-9]*$ ]] || cv_die "--per-page exige um inteiro >= 1 (recebido: $PER_PAGE)"

ml_fetch() { # ml_fetch <página> — GET /mercadolivre/products
  cv_get "/mercadolivre/products" --get \
    --data-urlencode "agentId=${AGENT_ID}" \
    --data-urlencode "serviceProviderId=${SP_ID}" \
    --data-urlencode "page=$1" \
    --data-urlencode "perPage=${PER_PAGE}"
}

ml_products_of() { # imprime o array "products" de um JSON
  printf '%s' "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    for k in ("products", "data", "results"):
        if isinstance(d.get(k), list):
            d = d[k]
            break
if not isinstance(d, list):
    d = []
print(json.dumps(d, ensure_ascii=False))
'
}

ml_field_of() { # ml_field_of <json> <campo>
  printf '%s' "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
d = d if isinstance(d, dict) else {}
v = d.get(sys.argv[1])
print("" if v is None else v)
' "$2"
}

ml_fetch "$PAGE"
ROOT=$(cv_unwrap "$CV_RESP")
PRODUCTS=$(ml_products_of "$ROOT")
TOTAL=$(ml_field_of "$ROOT" total)
RPAGE=$(ml_field_of "$ROOT" page)
RPER=$(ml_field_of "$ROOT" perPage)

if [ "$ALL" = "1" ]; then
  page="$PAGE"
  guard=0
  while :; do
    n=$(printf '%s' "$PRODUCTS" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
    [ "$n" = "0" ] && break
    [ -n "$TOTAL" ] && [ "$n" -ge "$TOTAL" ] && break
    [ "$n" -lt "$PER_PAGE" ] && break
    guard=$((guard + 1))
    [ "$guard" -gt 250 ] && { cv_warn "parando em 250 páginas (use --per-page maior para varrer mais rápido)"; break; }
    page=$((page + 1))
    ml_fetch "$page"
    PAGE_ROOT=$(cv_unwrap "$CV_RESP")
    PAGE_PRODUCTS=$(ml_products_of "$PAGE_ROOT")
    [ -n "$TOTAL" ] || TOTAL=$(ml_field_of "$PAGE_ROOT" total)
    [ -n "$RPER" ]  || RPER=$(ml_field_of "$PAGE_ROOT" perPage)
    PRODUCTS=$(python3 -c '
import json, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
print(json.dumps(a + b, ensure_ascii=False))
' "$PRODUCTS" "$PAGE_PRODUCTS")
  done
fi

COUNT=$(printf '%s' "$PRODUCTS" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$PRODUCTS"
  exit 0
fi

if [ "$FULL" = "1" ]; then
  if [ "$ALL" = "1" ]; then
    python3 - "$PRODUCTS" "${TOTAL:-}" <<'PY'
import json, sys
out = {"products": json.loads(sys.argv[1])}
if sys.argv[2]:
    out["total"] = int(sys.argv[2])
print(json.dumps(out, indent=2, ensure_ascii=False))
PY
  else
    printf '%s' "$ROOT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))'
  fi
  exit 0
fi

if [ "$COUNT" = "0" ]; then
  cv_info "Nenhum produto do Mercado Livre para o agente ${AGENT_ID} (service provider ${SP_ID})."
  exit 0
fi

cv_info "Produtos do Mercado Livre — agente ${AGENT_ID} · service provider ${SP_ID} — ${COUNT} de ${TOTAL:-?} (página ${RPAGE:-$PAGE}, perPage ${RPER:-$PER_PAGE})"

printf '%s' "$PRODUCTS" | python3 -c '
import json, sys

def cell(v):
    if v is None:
        return "-"
    return str(v)

items = json.load(sys.stdin)
rows = []
for p in items:
    price = p.get("price")
    if price is None:
        price = ""
    else:
        price = f"{float(price):.2f}"
    rows.append([
        cell(p.get("id")),
        cell(p.get("title")),
        price,
        cell(p.get("currency_id")),
        cell(p.get("available_quantity")),
        cell(p.get("permalink")),
    ])
head = ["ID", "TÍTULO", "PREÇO", "MOEDA", "ESTOQUE", "LINK"]
widths = [max(len(head[i]), *(len(r[i]) for r in rows)) if rows else len(head[i]) for i in range(len(head))]
line = "  ".join(h.ljust(widths[i]) for i, h in enumerate(head))
print(line)
print("-" * len(line))
for r in rows:
    print("  ".join(r[i].ljust(widths[i]) for i in range(len(head))))
'
