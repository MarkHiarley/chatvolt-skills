#!/usr/bin/env bash
# query-verify.sh — prova que o filtro custom_ids da query funciona na prática.
#
# POST /datastores/{id}/query com filters.custom_ids: id válido devolve trechos;
# id inexistente devolve [] (200). É a única forma de confirmar que o
# custom_id gravado na fonte realmente segmenta a recuperação.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: query-verify.sh <api-key> <datastore-id> <query>
     [--custom-id <id> | --custom-ids <a,b>] [--datasource-id <id> | --datasource-ids <a,b>]
     [--top-k <N>] [--max-chars <N>] [--expect-nonempty | --expect-empty]

Consulta a base (POST /datastores/{id}/query) mostrando os trechos recuperados
e, quando há filtro, se ele casou. Serve para verificar o custom_id gravado por
set-custom-id.sh e o efeito das etiquetas.

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)
  <datastore-id>     ID da base (sufixo _v3)
  <query>            Pergunta/texto da busca

Opções:
  --custom-id <id>       filtra filters.custom_ids=[<id>]
  --custom-ids <a,b>     filtra por vários custom_ids (qualquer um casa)
  --datasource-id <id>   filtra filters.datasource_ids=[<id>]
  --datasource-ids <a,b> idem, vários
  --top-k <N>            trechos pedidos (padrão 5)
  --max-chars <N>        tamanho do trecho impresso (padrão 300; 0 = texto completo)
  --expect-nonempty      sai 1 se nenhum trecho voltar (asserção)
  --expect-empty         sai 1 se algum trecho voltar (asserção)
  -h, --help             Mostra esta ajuda

Exemplos:
  query-verify.sh "$CHATVOLT_API_KEY" <base> "qual o prazo de garantia?"
  query-verify.sh "$CHATVOLT_API_KEY" <base> "qual o prazo?" --custom-id tenant-x
  query-verify.sh "$CHATVOLT_API_KEY" <base> "qual o prazo?" --custom-id tenant-x --expect-nonempty
  query-verify.sh "$CHATVOLT_API_KEY" <base> "qual o prazo?" --custom-id outro-tenant --expect-empty

Saída (CV_JSON=1):
  {"datastoreId","query","topK","filters","expect","count","results":[…]}
  — sem filtro, "filters" vem null; "results" traz text,score,datasource_name,
    datasource_id,custom_id,offset.

Exit: 0 ok · 1 erro/asserção falhou · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift
DS="${1:-}"; shift || true
QUERY="${1:-}"; shift || true
[ -n "$DS" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$QUERY" ] || { usage >&2; cv_die "informe a <query>"; }

CUSTOM_IDS=""; DATASOURCE_IDS=""
TOPK=5; MAXCHARS=300; EXPECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --custom-id)      CUSTOM_IDS="${2:-}"; shift 2 ;;
    --custom-ids)     CUSTOM_IDS="${2:-}"; shift 2 ;;
    --datasource-id)  DATASOURCE_IDS="${2:-}"; shift 2 ;;
    --datasource-ids) DATASOURCE_IDS="${2:-}"; shift 2 ;;
    --top-k)          TOPK="${2:-}"; shift 2 ;;
    --max-chars)      MAXCHARS="${2:-}"; shift 2 ;;
    --expect-nonempty) EXPECT=nonempty; shift ;;
    --expect-empty)    EXPECT=empty; shift ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

case "$TOPK" in ''|*[!0-9]*) cv_die "--top-k exige um número inteiro" ;; esac
[ "$TOPK" -ge 1 ] && [ "$TOPK" -le 50 ] || cv_die "--top-k deve ficar entre 1 e 50"
case "$MAXCHARS" in ''|*[!0-9]*) cv_die "--max-chars exige um número inteiro" ;; esac
[ -n "$CUSTOM_IDS" ] && [ -n "$DATASOURCE_IDS" ] && cv_warn "usando os dois filtros (custom_ids e datasource_ids)"

PAYLOAD=$(python3 - "$QUERY" "$TOPK" "$CUSTOM_IDS" "$DATASOURCE_IDS" <<'PY'
import json, sys

query, topk, custom_ids, datasource_ids = sys.argv[1:5]
payload = {"query": query, "topK": int(topk)}
filters = {}
if custom_ids.strip():
    filters["custom_ids"] = [p.strip() for p in custom_ids.split(",") if p.strip()]
if datasource_ids.strip():
    filters["datasource_ids"] = [p.strip() for p in datasource_ids.split(",") if p.strip()]
if filters:
    payload["filters"] = filters
print(json.dumps(payload, ensure_ascii=False))
PY
)

cv_request POST "/datastores/${DS}/query" "$PAYLOAD"

FILTERS_JSON=$(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys
print(json.dumps(json.load(sys.stdin).get("filters"), ensure_ascii=False))')

RESULT=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys
raw = json.load(sys.stdin)
if isinstance(raw, dict):
    if "data" in raw and "error" not in raw:
        raw = raw["data"] or []
    elif "error" in raw:
        sys.stderr.write("ERRO: " + json.dumps(raw, ensure_ascii=False) + "\n")
        raise SystemExit(1)
    else:
        raw = []
if not isinstance(raw, list):
    raw = [raw]
print(json.dumps({"datastoreId": sys.argv[1], "query": sys.argv[3], "topK": int(sys.argv[4]),
                  "filters": json.loads(sys.argv[2]), "expect": sys.argv[5] or None,
                  "count": len(raw), "results": raw}, ensure_ascii=False))' "$DS" "$FILTERS_JSON" "$QUERY" "$TOPK" "$EXPECT")

COUNT=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$RESULT"
else
  printf '%s' "$RESULT" | python3 -c 'import json,sys
d = json.load(sys.stdin)
mc = int(sys.argv[1])
print("Base:   " + str(d["datastoreId"]))
print("Query:  " + str(d["query"]))
print("Filtro: " + (json.dumps(d["filters"], ensure_ascii=False) if d["filters"] else "(nenhum — busca em todas as fontes)"))
print("topK:   " + str(d["topK"]))
print("")
print("Trechos: %d" % d["count"])
for i, r in enumerate(d["results"], 1):
    text = str(r.get("text") or "")
    if mc and len(text) > mc:
        text = text[:mc] + "…"
    print("[%d] score %.4f · %s (%s) · custom_id %s · offset %s"
          % (i, float(r.get("score") or 0), str(r.get("datasource_name") or "-"),
             str(r.get("datasource_id") or "-"), str(r.get("custom_id") or "-"), str(r.get("offset"))))
    print("    " + " ".join(text.split()))
if d["count"] == 0:
    print("")
    if d["filters"] and d["filters"].get("custom_ids"):
        print("O filtro custom_ids não retornou nada: confira o valor gravado nas fontes")
        print("(show-source-tags.sh) e as etiquetas (find-by-tag.sh / list-tags.sh).")
        print("custom_id é por fonte — um valor errado devolve exatamente [].")
    else:
        print("A base não devolveu trechos para essa consulta.")
if d["expect"] == "nonempty":
    print("")
    print("Asserção --expect-nonempty: " + ("OK" if d["count"] > 0 else "FALHOU (0 trechos)"))
elif d["expect"] == "empty":
    print("")
    print("Asserção --expect-empty: " + ("OK" if d["count"] == 0 else "FALHOU (%d trechos)" % d["count"]))
' "$MAXCHARS"
fi

case "$EXPECT" in
  nonempty) [ "$COUNT" -gt 0 ] || cv_die "esperava ao menos 1 trecho, veio 0 (filtro/consulta sem correspondência)" ;;
  empty)    [ "$COUNT" -eq 0 ] || cv_die "esperava 0 trechos, vieram $COUNT" ;;
esac
