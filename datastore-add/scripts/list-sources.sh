#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Listar as fontes (datasources) de uma base de conhecimento.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./list-sources.sh <api-key> <datastore-id> [--limit N] [--offset N] [--all] [--status S] [--tag T]

Lista as fontes de uma base de conhecimento, com status de indexação e tags.
  GET /datasources/list?datastoreId=&offset=&limit=  ->  {data:[...], pagination:{...}}
  (datastoreId é obrigatório nessa rota: sem ele a API responde 400)

Opções:
  --limit N    itens por página (padrão 20)
  --offset N   deslocamento inicial (padrão 0)
  --all        pagina automaticamente até o fim
  --status S   filtra localmente por status (pending|synched|error|running|unsynched)
  --tag T      filtra localmente por etiqueta (config.tags)
  -h, --help   mostra esta ajuda

Exemplos:
  ./list-sources.sh "$CHATVOLT_API_KEY" cmabc123_v3
  ./list-sources.sh "$CHATVOLT_API_KEY" cmabc123_v3 --all --status synched
  CV_JSON=1 ./list-sources.sh "$CHATVOLT_API_KEY" cmabc123_v3 --limit 100

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

LIMIT=20
OFFSET=0
ALL=0
STATUS=""
TAG=""
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --limit) [ "$#" -ge 2 ] || { echo "ERRO: --limit exige um valor" >&2; exit 1; }; LIMIT="$2"; shift 2 ;;
    --offset) [ "$#" -ge 2 ] || { echo "ERRO: --offset exige um valor" >&2; exit 1; }; OFFSET="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --status) [ "$#" -ge 2 ] || { echo "ERRO: --status exige um valor" >&2; exit 1; }; STATUS="$2"; shift 2 ;;
    --tag) [ "$#" -ge 2 ] || { echo "ERRO: --tag exige um valor" >&2; exit 1; }; TAG="$2"; shift 2 ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DS_ID="${POS[1]:-}"
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um número inteiro" ;; esac
case "$OFFSET" in ''|*[!0-9]*) cv_die "--offset deve ser um número inteiro" ;; esac
[ "$LIMIT" -gt 0 ] || cv_die "--limit deve ser maior que zero"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

PAGE=0
CUR="$OFFSET"
while :; do
  cv_get "/datasources/list?datastoreId=${DS_ID}&offset=${CUR}&limit=${LIMIT}"
  printf '%s' "$CV_RESP" > "${TMPD}/${PAGE}.json"
  [ "$ALL" = "1" ] || break
  stats=$(python3 - "${TMPD}/${PAGE}.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
p = d.get("pagination") or {}
print(int(p.get("count") or 0), int(p.get("total") or 0))
PY
)
  COUNT="${stats%% *}"
  TOTAL="${stats##* }"
  PAGE=$((PAGE + 1))
  CUR=$((CUR + COUNT))
  [ "$COUNT" -gt 0 ] || break
  [ "$CUR" -lt "$TOTAL" ] || break
done

if [ "$CV_JSON" = "1" ]; then
  python3 - "$TMPD" "$STATUS" "$TAG" <<'PY'
import glob, json, os, sys

tmpd, status, tag = sys.argv[1], sys.argv[2], sys.argv[3]
files = sorted(glob.glob(os.path.join(tmpd, "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items, total = [], 0
for f in files:
    d = json.load(open(f, encoding="utf-8"))
    items.extend(d.get("data") or [])
    total = int((d.get("pagination") or {}).get("total") or total)

def keep(s):
    if status and s.get("status") != status:
        return False
    if tag and tag not in ((s.get("config") or {}).get("tags") or []):
        return False
    return True

items = [s for s in items if keep(s)]
print(json.dumps({"data": items,
                  "pagination": {"total": total if total else len(items), "count": len(items)}},
                 ensure_ascii=False))
PY
else
  python3 - "$TMPD" "$STATUS" "$TAG" <<'PY'
import glob, json, os, sys

tmpd, status, tag = sys.argv[1], sys.argv[2], sys.argv[3]
files = sorted(glob.glob(os.path.join(tmpd, "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items = []
for f in files:
    items.extend(json.load(open(f, encoding="utf-8")).get("data") or [])

def keep(s):
    if status and s.get("status") != status:
        return False
    if tag and tag not in ((s.get("config") or {}).get("tags") or []):
        return False
    return True

shown = [s for s in items if keep(s)]
filtros = []
if status:
    filtros.append(f"status={status}")
if tag:
    filtros.append(f"tag={tag}")

def cut(v, n):
    s = "" if v is None else str(v)
    return s if len(s) <= n else s[:n - 1] + "…"

if not shown:
    print("Nenhuma fonte encontrada" + (f" (filtros: {', '.join(filtros)})" if filtros else "") + ".")
    raise SystemExit

print(f"=== Fontes ({len(shown)}" + (f" de {len(items)}; filtros: {', '.join(filtros)}" if filtros else "") + ") ===")
print(f"{'ID':<30} {'TIPO':<9} {'STATUS':<18} {'CHUNKS':>7} {'TOKENS':>7}  {'TAGS':<18} {'CUSTOM_ID':<14} {'SYNCH':<20} NOME")
print("-" * 168)
for s in shown:
    cfg = s.get("config") or {}
    tags = ",".join(cfg.get("tags") or []) or "-"
    print(f"{cut(s.get('id'), 29):<30} {cut(s.get('type'), 8):<9} {cut(s.get('status'), 17):<18} "
          f"{str(s.get('nbChunks', '-')):>7} {str(s.get('nbTokens', '-')):>7}  "
          f"{cut(tags, 17):<18} {cut(cfg.get('custom_id') or '-', 13):<14} "
          f"{cut(s.get('lastSynch') or '-', 19):<20} {cut(s.get('name'), 60)}")
print()
print("Legenda: CHUNKS=0 depois de synched significa que nada foi indexado (ver add-source.sh).")
PY
fi
