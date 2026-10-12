#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Listar bases de conhecimento (datastores) da organização.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./list-datastores.sh <api-key> [--limit N] [--offset N] [--all]

Lista as bases de conhecimento (datastores) da organização.
  GET /datastores/list?offset=&limit=  ->  {data:[...], pagination:{...}}

Opções:
  --limit N    itens por página (padrão 20)
  --offset N   deslocamento inicial (padrão 0)
  --all        pagina automaticamente até o fim
  -h, --help   mostra esta ajuda

Exemplos:
  ./list-datastores.sh "$CHATVOLT_API_KEY"
  ./list-datastores.sh "$CHATVOLT_API_KEY" --all
  CV_JSON=1 ./list-datastores.sh "$CHATVOLT_API_KEY" --limit 5

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

LIMIT=20
OFFSET=0
ALL=0
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --limit) [ "$#" -ge 2 ] || { echo "ERRO: --limit exige um valor" >&2; exit 1; }; LIMIT="$2"; shift 2 ;;
    --offset) [ "$#" -ge 2 ] || { echo "ERRO: --offset exige um valor" >&2; exit 1; }; OFFSET="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um número inteiro" ;; esac
case "$OFFSET" in ''|*[!0-9]*) cv_die "--offset deve ser um número inteiro" ;; esac
[ "$LIMIT" -gt 0 ] || cv_die "--limit deve ser maior que zero"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

PAGE=0
CUR="$OFFSET"
while :; do
  cv_get "/datastores/list?offset=${CUR}&limit=${LIMIT}"
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
  python3 - "$TMPD" <<'PY'
import glob, json, os, sys

files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items, total = [], 0
for f in files:
    d = json.load(open(f, encoding="utf-8"))
    items.extend(d.get("data") or [])
    total = int((d.get("pagination") or {}).get("total") or total)
print(json.dumps({"data": items,
                  "pagination": {"total": total if total else len(items), "count": len(items)}},
                 ensure_ascii=False))
PY
else
  python3 - "$TMPD" <<'PY'
import glob, json, os, sys

files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items = []
for f in files:
    items.extend(json.load(open(f, encoding="utf-8")).get("data") or [])

def cut(v, n):
    s = "" if v is None else str(v)
    return s if len(s) <= n else s[:n - 1] + "…"

if not items:
    print("Nenhuma base de conhecimento (datastore) encontrada.")
    raise SystemExit

print(f"{'ID':<30} {'NOME':<40} {'TIPO':<8} {'VISIB':<8} {'FONTES':>6}  CRIADO")
print("-" * 118)
for d in items:
    fontes = (d.get("_count") or {}).get("datasources", "?")
    print(f"{cut(d.get('id'), 29):<30} {cut(d.get('name'), 39):<40} "
          f"{cut(d.get('type'), 7):<8} {cut(d.get('visibility'), 7):<8} "
          f"{str(fontes):>6}  {cut(d.get('createdAt'), 24)}")
print()
print(f"{len(items)} base(s) de conhecimento.")
PY
fi
