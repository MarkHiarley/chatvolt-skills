#!/usr/bin/env bash
set -euo pipefail

# chatvolt-mercadolivre — get-products.sh
# Busca produtos do Mercado Livre já sincronizados, com filtro fuzzy
# (GET /mercadolivre/get-products?agentId=…).
#
# Verificado ao vivo em 2026-10-12 (organização de teste, sem integração ML):
#   - sem agentId → 400 {"error":"Agent ID is required"}
#   - com agentId → 404 {"error":"Mercado Livre service provider not found for
#                         this agent"}
# O 404 é tratado abaixo com uma mensagem acionável (agente sem integração).

usage() {
  cat <<'EOF'
Uso: get-products.sh <api-key> <agent-id> [opções]

Busca produtos do Mercado Livre integrados ao agente, com filtro fuzzy
("get-products" é a rota antiga; /mercadolivre/products é a paginada).

Opções:
  --agent <id>                 id do agente (alternativa ao 2º argumento).
  --query <termo>              termo de busca fuzzy.
  --threshold <float>          limite mínimo de relevância (default da API: 0.3).
  --max-results <n>            máximo de resultados.
  --sort-by-relevance <bool>   ordena por relevância (default da API: true).
  --typo-tolerance <n|bool>    tolerância a erro de digitação (default da API: 1;
                               o openapi declara inteiro, a doc narrativa boolean).
  --case-sensitive <bool>      busca sensível a maiúsculas (default: false).
  --partial-match <bool>       aceita correspondência parcial (default: true).
  -h, --help                   esta ajuda.

Booleanos aceitam true|false.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_JSON=1           imprime SOMENTE JSON em stdout (array de produtos)
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Só os filtros informados vão na query — os defaults são os da própria API.
Resposta: {"products":[…]} (a doc diz que não usa o envelope padrão).

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplos:
  get-products.sh "$KEY" "$AG"
  get-products.sh "$KEY" "$AG" --query "panela de pressão" --max-results 5
  get-products.sh "$KEY" "$AG" --query panela --threshold 0.5 --typo-tolerance 2
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

QUERY=""
THRESHOLD=""
MAX_RESULTS=""
SORT=""
TYPO=""
CASE_SENS=""
PARTIAL=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)              [ -n "${2:-}" ] || cv_die "--agent exige um valor"; AGENT_ID="$2"; shift 2 ;;
    --query)              [ -n "${2:-}" ] || cv_die "--query exige um valor"; QUERY="$2"; shift 2 ;;
    --threshold)          [ -n "${2:-}" ] || cv_die "--threshold exige um valor"; THRESHOLD="$2"; shift 2 ;;
    --max-results)        [ -n "${2:-}" ] || cv_die "--max-results exige um valor"; MAX_RESULTS="$2"; shift 2 ;;
    --sort-by-relevance)  [ -n "${2:-}" ] || cv_die "--sort-by-relevance exige um valor"; SORT="$2"; shift 2 ;;
    --typo-tolerance)     [ -n "${2:-}" ] || cv_die "--typo-tolerance exige um valor"; TYPO="$2"; shift 2 ;;
    --case-sensitive)     [ -n "${2:-}" ] || cv_die "--case-sensitive exige um valor"; CASE_SENS="$2"; shift 2 ;;
    --partial-match)      [ -n "${2:-}" ] || cv_die "--partial-match exige um valor"; PARTIAL="$2"; shift 2 ;;
    -h|--help)            usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

AGENT_ID="${AGENT_ID:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id como 2º argumento ou exporte CHATVOLT_AGENT_ID"

[[ "$THRESHOLD" =~ ^[0-9]+([.][0-9]+)?$ ]]      || { [ -z "$THRESHOLD" ] || cv_die "--threshold exige um número (ex.: 0.3)"; }
[[ "$MAX_RESULTS" =~ ^[1-9][0-9]*$ ]]           || { [ -z "$MAX_RESULTS" ] || cv_die "--max-results exige um inteiro >= 1"; }
[[ "$TYPO" =~ ^[0-9]+$ || "$TYPO" == "true" || "$TYPO" == "false" ]] || { [ -z "$TYPO" ] || cv_die "--typo-tolerance aceita inteiro >= 0, true ou false"; }
for pair in "sort-by-relevance:$SORT" "case-sensitive:$CASE_SENS" "partial-match:$PARTIAL"; do
  opt="${pair%%:*}"; val="${pair#*:}"
  [ -z "$val" ] || [[ "$val" == "true" || "$val" == "false" ]] || cv_die "--${opt} aceita true ou false (recebido: $val)"
done

ARGS=(--get --data-urlencode "agentId=${AGENT_ID}")
[ -n "$QUERY" ]       && ARGS+=(--data-urlencode "query=${QUERY}")
[ -n "$THRESHOLD" ]   && ARGS+=(--data-urlencode "threshold=${THRESHOLD}")
[ -n "$MAX_RESULTS" ] && ARGS+=(--data-urlencode "maxResults=${MAX_RESULTS}")
[ -n "$SORT" ]        && ARGS+=(--data-urlencode "sortByRelevance=${SORT}")
[ -n "$TYPO" ]        && ARGS+=(--data-urlencode "typoTolerance=${TYPO}")
[ -n "$CASE_SENS" ]   && ARGS+=(--data-urlencode "caseSensitive=${CASE_SENS}")
[ -n "$PARTIAL" ]     && ARGS+=(--data-urlencode "partialMatch=${PARTIAL}")

# GET que não aborta em erro HTTP: precisamos inspecionar o corpo do 404 para
# distinguir "agente sem integração do Mercado Livre" de outros erros.
# Deixa o corpo em ML_TEXT, o código em ML_RC e ML_OK=1 quando deu certo.
ML_TEXT=""
ML_OK=0
ML_RC=0
ml_get_soft() {
  local out
  set +e
  out=$( { cv_get "$@"; printf '\n@@CV_OK@@\n%s' "$CV_RESP"; } 2>&1 )
  ML_RC=$?
  set -e
  case "$out" in
    *@@CV_OK@@*)
      ML_OK=1
      ML_TEXT="${out#*@@CV_OK@@$'\n'}"
      ;;
    *)
      ML_OK=0
      ML_TEXT="$out"
      ;;
  esac
}

ml_get_soft "/mercadolivre/get-products" "${ARGS[@]}"
TEXT="$ML_TEXT"

if [ "$ML_OK" != "1" ]; then
  case "$TEXT" in
    *"service provider not found"*)
      cv_die "o agente ${AGENT_ID} não tem integração do Mercado Livre conectada — GET /mercadolivre/get-products respondeu 404 \"Mercado Livre service provider not found for this agent\". Conecte a integração do Mercado Livre e rode sync-products.sh antes de buscar."
      ;;
    *)
      printf '%s\n' "$TEXT" >&2
      exit "$ML_RC"
      ;;
  esac
fi

ROOT=$(cv_unwrap "$TEXT")
PRODUCTS=$(printf '%s' "$ROOT" | python3 -c '
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
')
COUNT=$(printf '%s' "$PRODUCTS" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$PRODUCTS"
  exit 0
fi

if [ "$COUNT" = "0" ]; then
  if [ -n "$QUERY" ]; then
    cv_info "Nenhum produto encontrado para \"${QUERY}\" no agente ${AGENT_ID}."
  else
    cv_info "Nenhum produto do Mercado Livre encontrado para o agente ${AGENT_ID}."
  fi
  exit 0
fi

cv_info "Produtos do Mercado Livre — agente ${AGENT_ID}${QUERY:+ · busca \"$QUERY\"} — ${COUNT} resultado(s)"

printf '%s' "$PRODUCTS" | python3 -c '
import json, sys

def cell(v):
    return "-" if v is None else str(v)

items = json.load(sys.stdin)
rows = []
for p in items:
    price = p.get("price")
    price = "" if price is None else f"{float(price):.2f}"
    rows.append([
        cell(p.get("id")),
        cell(p.get("title")),
        price,
        cell(p.get("currency_id")),
        cell(p.get("permalink")),
    ])
head = ["ID", "TÍTULO", "PREÇO", "MOEDA", "LINK"]
widths = [max(len(head[i]), *(len(r[i]) for r in rows)) for i in range(len(head))]
line = "  ".join(h.ljust(widths[i]) for i, h in enumerate(head))
print(line)
print("-" * len(line))
for r in rows:
    print("  ".join(r[i].ljust(widths[i]) for i in range(len(head))))
'
