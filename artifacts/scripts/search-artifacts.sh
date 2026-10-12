#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — search-artifacts
#
# Busca artefatos (GET /artifacts/search) com filtros avançados: texto livre,
# ids explícitos, faixa de preço, categorias (inclui subcategorias) e tipos de
# mídia. A resposta é {"data":[...],"meta":{total,page,limit,totalPages,...}}.
#
# Uso:
#   search-artifacts.sh [api-key] [opções]
#
# Opções:
#   --q <termo>             busca em nome, descrição e nome da categoria
#   --ids <id1,id2>         ids específicos (ignora --q)
#   --category-ids <a,b>    ids de categoria (inclui subcategorias)
#   --media-types <tipos>   IMAGE,VIDEO,AUDIO,DOCUMENT,OTHER (separados por vírgula)
#   --min-price <n>         preço mínimo
#   --max-price <n>         preço máximo
#   --max-medias <n>        mídias por artefato (1-50, padrão da API: 10)
#   --include-inactive      inclui artefatos inativos
#   --limit <n>             itens por página (1-100, padrão 20)
#   --page <n>              página (padrão 1)
#   --all                   percorre todas as páginas
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
search-artifacts.sh — busca artefatos do Chatvolt (GET /artifacts/search)

Uso:
  search-artifacts.sh [api-key] [opções]

Opções:
  --q <termo>             termo de busca (nome, descrição ou categoria)
  --ids <id1,id2>         ids específicos (a API ignora --q quando --ids existe)
  --category-ids <a,b>    ids de categoria (busca recursiva em subcategorias)
  --media-types <tipos>   IMAGE,VIDEO,AUDIO,DOCUMENT,OTHER (vírgula)
  --min-price <n>         preço mínimo
  --max-price <n>         preço máximo
  --max-medias <n>        mídias por artefato (1-50, padrão 10)
  --include-inactive      inclui artefatos inativos
  --limit <n>             itens por página (1-100, padrão 20)
  --page <n>              página (padrão 1)
  --all                   percorre todas as páginas (usa meta.totalPages)
  -h, --help              mostra esta ajuda

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

Q=""
IDS=""
CATEGORY_IDS=""
MEDIA_TYPES=""
MIN_PRICE=""
MAX_PRICE=""
MAX_MEDIAS=""
INCLUDE_INACTIVE=0
LIMIT="20"
PAGE="1"
ALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --q)                Q="${2:?--q exige um termo}"; shift 2 ;;
    --ids)              IDS="${2:?--ids exige uma lista separada por vírgula}"; shift 2 ;;
    --category-ids)     CATEGORY_IDS="${2:?--category-ids exige uma lista separada por vírgula}"; shift 2 ;;
    --media-types)      MEDIA_TYPES="${2:?--media-types exige uma lista separada por vírgula}"; shift 2 ;;
    --min-price)        MIN_PRICE="${2:?--min-price exige um número}"; shift 2 ;;
    --max-price)        MAX_PRICE="${2:?--max-price exige um número}"; shift 2 ;;
    --max-medias)       MAX_MEDIAS="${2:?--max-medias exige um número}"; shift 2 ;;
    --include-inactive) INCLUDE_INACTIVE=1; shift ;;
    --limit)            LIMIT="${2:?--limit exige um número}"; shift 2 ;;
    --page)             PAGE="${2:?--page exige um número}"; shift 2 ;;
    --all)              ALL=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um inteiro entre 1 e 100" ;; esac
[ "$LIMIT" -ge 1 ] && [ "$LIMIT" -le 100 ] || cv_die "--limit deve estar entre 1 e 100 (máximo da API)"
case "$PAGE" in ''|*[!0-9]*) cv_die "--page deve ser um inteiro >= 1" ;; esac
[ "$PAGE" -ge 1 ] || cv_die "--page deve ser >= 1"
if [ -n "$MAX_MEDIAS" ]; then
  case "$MAX_MEDIAS" in ''|*[!0-9]*) cv_die "--max-medias deve ser um inteiro entre 1 e 50" ;; esac
  [ "$MAX_MEDIAS" -ge 1 ] && [ "$MAX_MEDIAS" -le 50 ] || cv_die "--max-medias deve estar entre 1 e 50 (máximo da API)"
fi
if [ -n "$MEDIA_TYPES" ]; then
  # A API responde 500 com um tipo fora do enum — validamos aqui (exit 1).
  IFS=',' read -r -a __types <<<"$MEDIA_TYPES"
  for t in "${__types[@]}"; do
    case "$t" in
      IMAGE|VIDEO|AUDIO|DOCUMENT|OTHER) ;;
      *) cv_die "--media-types inválido: $t (use IMAGE, VIDEO, AUDIO, DOCUMENT ou OTHER)" ;;
    esac
  done
fi
if [ -n "$IDS" ]; then
  [ -n "$Q" ] && cv_warn "--ids informado: a API ignora --q na busca"
  case "$IDS" in ,*|*,|*,,*) cv_die "--ids contém id vazio" ;; esac
fi

build_args() {
  local page="$1"
  ARGS=(--get --data-urlencode "limit=${LIMIT}" --data-urlencode "page=${page}")
  if [ -n "$Q" ];            then ARGS+=(--data-urlencode "q=${Q}"); fi
  if [ -n "$IDS" ];          then ARGS+=(--data-urlencode "ids=${IDS}"); fi
  if [ -n "$CATEGORY_IDS" ]; then ARGS+=(--data-urlencode "categoryIds=${CATEGORY_IDS}"); fi
  if [ -n "$MEDIA_TYPES" ];  then ARGS+=(--data-urlencode "mediaTypes=${MEDIA_TYPES}"); fi
  if [ -n "$MIN_PRICE" ];    then ARGS+=(--data-urlencode "minPrice=${MIN_PRICE}"); fi
  if [ -n "$MAX_PRICE" ];    then ARGS+=(--data-urlencode "maxPrice=${MAX_PRICE}"); fi
  if [ -n "$MAX_MEDIAS" ];   then ARGS+=(--data-urlencode "maxMedias=${MAX_MEDIAS}"); fi
  if [ "$INCLUDE_INACTIVE" = "1" ]; then ARGS+=(--data-urlencode "includeInactive=true"); fi
  return 0
}

read -r -d '' FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d:
    items, meta = d["data"], d.get("meta") or {}
else:
    items, meta = d, {}
if not items:
    print("Nenhum artefato encontrado.")
else:
    print(f"{'ID':26} {'NOME':34} {'CATEGORIA':22} {'ATIVO':6} PRECO")
    for a in items:
        cat = (a.get("category") or {}).get("name") or a.get("categoryId") or "-"
        price = a.get("price")
        print(f"{a.get('id',''):26} {str(a.get('name',''))[:34]:34} {str(cat)[:22]:22} "
              f"{'sim' if a.get('isActive') else 'nao':6} {price if price is not None else '-'}")
    print(f"\nResultados nesta página: {len(items)}")
if meta:
    print(f"total: {meta.get('total')} · página {meta.get('page')} de {meta.get('totalPages')} "
          f"· limite {meta.get('limit')} · maxMedias {meta.get('maxMedias')}")
PY

if [ "$ALL" = "0" ]; then
  build_args "$PAGE"
  cv_get "/artifacts/search" "${ARGS[@]}"
  cv_emit "$CV_RESP" "$FORMATTER"
  exit 0
fi

TMPF=$(mktemp)
trap 'rm -f "$TMPF"' EXIT
PAGE=1
LAST_META="{}"
while :; do
  build_args "$PAGE"
  cv_get "/artifacts/search" "${ARGS[@]}"
  printf '%s\n' "$CV_RESP" >> "$TMPF"
  LAST_META=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("meta") or {}))')
  TOTAL_PAGES=$(printf '%s' "$LAST_META" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("totalPages") or 1)')
  N=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("data") or []))')
  if [ "$N" -eq 0 ] || [ "$PAGE" -ge "$TOTAL_PAGES" ]; then break; fi
  PAGE=$((PAGE + 1))
  if [ "$PAGE" -ge 200 ]; then cv_warn "limite de 200 páginas atingido — parando"; break; fi
done

MERGED=$(python3 - "$TMPF" <<'PY'
import json, sys
items, seen, meta = [], set(), {}
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    meta = d.get("meta") or meta
    for a in d.get("data") or []:
        if a.get("id") not in seen:
            seen.add(a.get("id"))
            items.append(a)
print(json.dumps({"data": items, "meta": meta}, ensure_ascii=False))
PY
)
cv_warn "paginação concluída: $(printf '%s' "$MERGED" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))') artefato(s)"
cv_emit "$MERGED" "$FORMATTER"
