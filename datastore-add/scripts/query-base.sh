#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Consultar uma base de conhecimento (busca semântica).
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./query-base.sh <api-key> <datastore-id> <query> [--top-k N] [--custom-id X[,Y]] [--datasource-id Y[,Z]]

Busca os trechos mais similares da pergunta na base.
  POST /datastores/{id}/query  ->  ARRAY na raiz:
  [{text, score, datasource_name, datasource_id, custom_id, offset}, ...]

Opções:
  --top-k N             número máximo de trechos (padrão 5)
  --custom-id X[,Y]     filtra por config.custom_id (multi-tenant; filters.custom_ids)
  --datasource-id Y[,Z] filtra por fontes específicas (filters.datasource_ids)
  -h, --help            mostra esta ajuda

Exemplos:
  ./query-base.sh "$CHATVOLT_API_KEY" cmabc123_v3 "Qual o prazo de garantia?"
  ./query-base.sh "$CHATVOLT_API_KEY" cmabc123_v3 "prazo" --top-k 10 --custom-id tenant-1
  CV_JSON=1 ./query-base.sh "$CHATVOLT_API_KEY" cmabc123_v3 "prazo" --top-k 3

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

TOPK=5
CUSTOM_IDS=""
DATASOURCE_IDS=""
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --top-k) [ "$#" -ge 2 ] || { echo "ERRO: --top-k exige um valor" >&2; exit 1; }; TOPK="$2"; shift 2 ;;
    --custom-id) [ "$#" -ge 2 ] || { echo "ERRO: --custom-id exige um valor" >&2; exit 1; }; CUSTOM_IDS="$2"; shift 2 ;;
    --datasource-id) [ "$#" -ge 2 ] || { echo "ERRO: --datasource-id exige um valor" >&2; exit 1; }; DATASOURCE_IDS="$2"; shift 2 ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DS_ID="${POS[1]:-}"
QUERY="${POS[2]:-}"
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$QUERY" ] || { usage >&2; cv_die "informe a <query>"; }
case "$TOPK" in ''|*[!0-9]*) cv_die "--top-k deve ser um número inteiro" ;; esac
[ "$TOPK" -gt 0 ] || cv_die "--top-k deve ser maior que zero"

BODY=$(python3 - "$QUERY" "$TOPK" "$CUSTOM_IDS" "$DATASOURCE_IDS" <<'PY'
import json, sys

query, topk, custom_ids, datasource_ids = sys.argv[1:5]
filters = {}
if custom_ids:
    filters["custom_ids"] = [v.strip() for v in custom_ids.split(",") if v.strip()]
if datasource_ids:
    filters["datasource_ids"] = [v.strip() for v in datasource_ids.split(",") if v.strip()]
body = {"query": query, "topK": int(topk)}
if filters:
    body["filters"] = filters
print(json.dumps(body, ensure_ascii=False))
PY
)

cv_request POST "/datastores/${DS_ID}/query" "$BODY"

FORMAT=$(cat <<'PY'
import json, signal, sys, textwrap

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
if not isinstance(d, list):
    print("❌ Resposta inesperada da consulta:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
    raise SystemExit(1)

if not d:
    print("Nenhum trecho retornado. A base pode estar vazia, os filtros podem não casar,")
    print("ou a indexação das fontes pode não ter gerado chunks (veja ./list-sources.sh).")
    raise SystemExit

print(f"=== {len(d)} trecho(s) ===")
for i, c in enumerate(d, 1):
    score = c.get("score")
    try:
        score_txt = f"{float(score):.4f}"
    except (TypeError, ValueError):
        score_txt = str(score)
    print()
    print(f"[{i}] score={score_txt}  offset={c.get('offset')}  fonte={c.get('datasource_name') or '-'} "
          f"({c.get('datasource_id') or '-'})  custom_id={c.get('custom_id') or '-'}  tags={','.join(c.get('tags') or []) or '-'}")
    text = " ".join(str(c.get("text") or "").split())
    for line in textwrap.wrap(text[:1200], 110) or [""]:
        print(f"    {line}")
PY
)

cv_emit "$CV_RESP" "$FORMAT"
