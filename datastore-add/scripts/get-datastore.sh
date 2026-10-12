#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Detalhar uma base de conhecimento (datastore) e suas fontes.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./get-datastore.sh <api-key> <datastore-id> [--limit N] [--search S] [--status S] [--type T]

Mostra os metadados de uma base de conhecimento e lista as fontes que ela contém.
  GET /datastores/{id}?limit=&search=&status=&type=  ->  objeto na raiz
  (a resposta traz "datasources":[...] já filtradas/paginadas pelo servidor)

Opções:
  --limit N     fontes a exibir (padrão 20)
  --search S    filtra fontes por texto no nome
  --status S    filtra fontes por status (pending|synched|error|running|unsynched)
  --type T      filtra fontes por tipo (file|qa|web_page|web_site)
  -h, --help    mostra esta ajuda

Exemplos:
  ./get-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3
  ./get-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3 --search manual --limit 50
  CV_JSON=1 ./get-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

LIMIT=20
SEARCH=""
STATUS=""
TYPE=""
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --limit) [ "$#" -ge 2 ] || { echo "ERRO: --limit exige um valor" >&2; exit 1; }; LIMIT="$2"; shift 2 ;;
    --search) [ "$#" -ge 2 ] || { echo "ERRO: --search exige um valor" >&2; exit 1; }; SEARCH="$2"; shift 2 ;;
    --status) [ "$#" -ge 2 ] || { echo "ERRO: --status exige um valor" >&2; exit 1; }; STATUS="$2"; shift 2 ;;
    --type) [ "$#" -ge 2 ] || { echo "ERRO: --type exige um valor" >&2; exit 1; }; TYPE="$2"; shift 2 ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DS_ID="${POS[1]:-}"
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um número inteiro" ;; esac
case "$STATUS" in ''|pending|running|synched|error|unsynched|usage_limit_reached) : ;; *) cv_die "--status inválido: '$STATUS' (use pending|running|synched|error|unsynched|usage_limit_reached)" ;; esac
case "$TYPE" in ''|file|qa|web_page|web_site) : ;; *) cv_die "--type inválido: '$TYPE' (use file|qa|web_page|web_site)" ;; esac

QUERY="/datastores/${DS_ID}?limit=${LIMIT}"
[ -n "$SEARCH" ] && QUERY="${QUERY}&search=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$SEARCH")"
[ -n "$STATUS" ] && QUERY="${QUERY}&status=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$STATUS")"
[ -n "$TYPE" ] && QUERY="${QUERY}&type=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$TYPE")"

cv_get "$QUERY"

FORMAT=$(cat <<'PY'
import json, sys

d = json.load(sys.stdin)

def cut(v, n):
    s = "" if v is None else str(v)
    return s if len(s) <= n else s[:n - 1] + "…"

dsc = d.get("datasources") or []
count = (d.get("_count") or {}).get("datasources")

print("=== Base de conhecimento ===")
print(f"id:          {d.get('id')}")
print(f"nome:        {d.get('name')}")
print(f"tipo:        {d.get('type')}   visibilidade: {d.get('visibility')}   autosync: {d.get('autosync')}")
print(f"pluginName:  {d.get('pluginName')}")
if d.get("pluginDescriptionForHumans"):
    print(f"pluginDesc:  {d.get('pluginDescriptionForHumans')}")
print(f"criado em:   {d.get('createdAt')}   atualizado em: {d.get('updatedAt')}")
print(f"fontes:      {count if count is not None else len(dsc)}")
if d.get("description"):
    print()
    print("descrição:")
    print(f"  {cut(d.get('description'), 400)}")
print()
print(f"=== Fontes exibidas ({len(dsc)}) ===")
if not dsc:
    print("(nenhuma fonte nesta página — aumente --limit ou limpe os filtros)")
else:
    print(f"{'ID':<30} {'TIPO':<9} {'STATUS':<18} {'CHUNKS':>7} {'TOKENS':>7}  {'TAGS':<16} {'CUSTOM_ID':<14} NOME")
    print("-" * 140)
    for s in dsc:
        cfg = s.get("config") or {}
        tags = ",".join(cfg.get("tags") or []) or "-"
        print(f"{cut(s.get('id'), 29):<30} {cut(s.get('type'), 8):<9} {cut(s.get('status'), 17):<18} "
              f"{str(s.get('nbChunks', '-')):>7} {str(s.get('nbTokens', '-')):>7}  "
              f"{cut(tags, 15):<16} {cut(cfg.get('custom_id') or '-', 13):<14} {cut(s.get('name'), 60)}")
PY
)

cv_emit "$CV_RESP" "$FORMAT"
