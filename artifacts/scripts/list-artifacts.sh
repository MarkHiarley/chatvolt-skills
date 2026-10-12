#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — list-artifacts
#
# Lista artefatos da organização (GET /artifacts) com os filtros que a rota
# aceita: categoryId (exato), name (exato) e search (nome, descrição ou id).
# A resposta real é {"data":[...],"total":N} — o total vem do servidor.
#
# Uso:
#   list-artifacts.sh [api-key] [opções]
#
# Opções:
#   --category <id>   filtra por categoria (categoryId)
#   --name <nome>     filtra por nome EXATO (name)
#   --search <termo>  busca livre em nome, descrição e id (search)
#   --limit <n>       itens por página (1-100, padrão 50)
#   --offset <n>      itens a pular (padrão 0)
#   --all             pagina via offset até cobrir o total
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
list-artifacts.sh — lista artefatos do Chatvolt (GET /artifacts)

Uso:
  list-artifacts.sh [api-key] [opções]

Opções:
  --category <id>   filtra por categoria (categoryId)
  --name <nome>     filtra por nome exato (name)
  --search <termo>  busca livre em nome, descrição e id (search)
  --limit <n>       itens por página (1-100, padrão 50)
  --offset <n>      itens a pular (padrão 0)
  --all             pagina via offset até cobrir o total informado pela API
  -h, --help        mostra esta ajuda

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

CATEGORY=""
NAME=""
SEARCH=""
LIMIT="50"
OFFSET="0"
ALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --category) CATEGORY="${2:?--category exige um id de categoria}"; shift 2 ;;
    --name)     NAME="${2:?--name exige um nome}"; shift 2 ;;
    --search)   SEARCH="${2:?--search exige um termo}"; shift 2 ;;
    --limit)    LIMIT="${2:?--limit exige um número}"; shift 2 ;;
    --offset)   OFFSET="${2:?--offset exige um número}"; shift 2 ;;
    --all)      ALL=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um inteiro entre 1 e 100" ;; esac
[ "$LIMIT" -ge 1 ] && [ "$LIMIT" -le 100 ] || cv_die "--limit deve estar entre 1 e 100"
case "$OFFSET" in ''|*[!0-9]*) cv_die "--offset deve ser um inteiro >= 0" ;; esac

read -r -d '' FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if not d:
    print("Nenhum artefato encontrado.")
    raise SystemExit
print(f"{'ID':26} {'NOME':34} {'CATEGORIA':22} {'ATIVO':6} {'MIDIAS':6} CRIADO EM")
for a in d:
    cat = (a.get("category") or {}).get("name") or a.get("categoryId") or "-"
    count = (a.get("_count") or {}).get("media")
    if count is None:
        count = len(a.get("media") or [])
    created = (a.get("createdAt") or "")[:16].replace("T", " ")
    print(f"{a.get('id',''):26} {str(a.get('name',''))[:34]:34} {str(cat)[:22]:22} "
          f"{'sim' if a.get('isActive') else 'nao':6} {count:6} {created}")
print(f"\nTotal: {len(d)}")
PY

build_args() {
  local off="$1"
  ARGS=(--get --data-urlencode "limit=${LIMIT}" --data-urlencode "offset=${off}")
  if [ -n "$CATEGORY" ]; then ARGS+=(--data-urlencode "categoryId=${CATEGORY}"); fi
  if [ -n "$NAME" ];     then ARGS+=(--data-urlencode "name=${NAME}"); fi
  if [ -n "$SEARCH" ];   then ARGS+=(--data-urlencode "search=${SEARCH}"); fi
  return 0
}

if [ "$ALL" = "0" ]; then
  build_args "$OFFSET"
  cv_get "/artifacts" "${ARGS[@]}"
  read -r N TOTAL <<<"$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(len(d.get("data") or []), d.get("total") or 0)
')"
  MERGED=$(cv_unwrap "$CV_RESP")
  cv_emit "$MERGED" "$FORMATTER"
  if [ "$TOTAL" -gt 0 ]; then cv_warn "mostrando ${N} de ${TOTAL} artefato(s)"; fi
  exit 0
fi

# --all: pagina por offset até cobrir o total devolvido pela API.
TMPF=$(mktemp)
trap 'rm -f "$TMPF"' EXIT
OFF=0
PAGE=0
TOTAL=0
while :; do
  PAGE=$((PAGE + 1))
  build_args "$OFF"
  cv_get "/artifacts" "${ARGS[@]}"
  read -r N TOTAL <<<"$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(len(d.get("data") or []), d.get("total") or 0)
')"
  cv_unwrap "$CV_RESP" >> "$TMPF"
  printf '\n' >> "$TMPF"
  if [ "$N" -lt "$LIMIT" ]; then break; fi
  OFF=$((OFF + N))
  if [ "$TOTAL" -gt 0 ] && [ "$OFF" -ge "$TOTAL" ]; then break; fi
  if [ "$PAGE" -ge 200 ]; then cv_warn "limite de 200 páginas atingido — parando"; break; fi
done

MERGED=$(python3 - "$TMPF" <<'PY'
import json, sys
items, seen = [], set()
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    for a in json.loads(line):
        if a.get("id") not in seen:
            seen.add(a.get("id"))
            items.append(a)
print(json.dumps(items, ensure_ascii=False))
PY
)
TOTAL_FOUND=$(printf '%s' "$MERGED" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
cv_warn "paginação concluída: ${TOTAL_FOUND} artefato(s) em ${PAGE} página(s)"
cv_emit "$MERGED" "$FORMATTER"
