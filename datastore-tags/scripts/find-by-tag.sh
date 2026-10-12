#!/usr/bin/env bash
# find-by-tag.sh — encontra as fontes de uma base que têm determinada etiqueta.
#
# A API NÃO filtra fontes por etiqueta (config.tags é metadado local), então a
# busca é feita no cliente sobre GET /datasources/list paginado.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: find-by-tag.sh <api-key> <datastore-id> <etiqueta>[,<etiqueta>…] [--page-size <N>]

Lista as fontes que possuem a(s) etiqueta(s) informada(s) (qualquer uma delas).
Filtro local: a API não busca por etiqueta — ela só é metadado da fonte.

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)
  <datastore-id>     ID da base (sufixo _v3)
  <etiqueta…>        etiquetas separadas por vírgula (casa exata, sem curinga)

Opções:
  --page-size <N>    Itens por página na listagem (padrão 100; máx. 100)
  -h, --help         Mostra esta ajuda

Exemplos:
  find-by-tag.sh "$CHATVOLT_API_KEY" cmszh5s6q0fbdvapf36roho4y_v3 financeiro
  CV_JSON=1 find-by-tag.sh "$CHATVOLT_API_KEY" <base> a,b

Saída (CV_JSON=1):
  {"datastoreId","tags","totalSources","matchedSources",
   "sources":[{id,name,type,status,nbChunks,textSize,custom_id,tags,matched}]}

Exit: 0 ok (inclusive sem resultados) · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor
EOF
}

# cv_all_sources <datastore-id> <tamanho-pagina> — array JSON com TODAS as fontes.
cv_all_sources() {
  local ds="$1" size="$2" offset=0 total=0 count=0 tmp
  tmp="$(mktemp)" || cv_die "não foi possível criar arquivo temporário"
  while :; do
    cv_get "/datasources/list?datastoreId=${ds}&offset=${offset}&limit=${size}"
    printf '%s\n' "$CV_RESP" >>"$tmp"
    read -r count total <<<"$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys
d = json.load(sys.stdin)
p = d.get("pagination") or {}
print(len(d.get("data") or []), p.get("total") or 0)')"
    offset=$((offset + count))
    [ "$count" -eq 0 ] && break
    [ "$offset" -ge "$total" ] && break
    [ "$offset" -ge 10000 ] && break
  done
  python3 -c 'import json,sys
out = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if line:
        out.extend(json.loads(line).get("data") or [])
print(json.dumps(out, ensure_ascii=False))' "$tmp"
  rm -f "$tmp"
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift
DS="${1:-}"; shift || true
WANT="${1:-}"; shift || true
[ -n "$DS" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$WANT" ] || { usage >&2; cv_die "informe a(s) etiqueta(s) a procurar"; }

PAGE=100
while [ $# -gt 0 ]; do
  case "$1" in
    --page-size) PAGE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done
case "$PAGE" in ''|*[!0-9]*) cv_die "--page-size exige um número inteiro" ;; esac
[ "$PAGE" -ge 1 ] && [ "$PAGE" -le 100 ] || cv_die "--page-size deve ficar entre 1 e 100"

SOURCES="$(cv_all_sources "$DS" "$PAGE")"

RESULT="$(printf '%s' "$SOURCES" | python3 -c 'import json,sys
srcs = json.load(sys.stdin)
ds = sys.argv[1]
want = [p.strip() for p in sys.argv[2].split(",") if p.strip()]
found = []
for s in srcs:
    cfg = s.get("config") or {}
    tags = [str(t) for t in (cfg.get("tags") or [])]
    matched = [t for t in want if t in tags]
    if not matched:
        continue
    found.append({"id": s.get("id"), "name": s.get("name"), "type": s.get("type"),
                  "status": s.get("status"), "nbChunks": s.get("nbChunks"),
                  "textSize": s.get("textSize"), "custom_id": cfg.get("custom_id") or None,
                  "tags": tags, "matched": matched})
print(json.dumps({"datastoreId": ds, "tags": want, "totalSources": len(srcs),
                  "matchedSources": len(found), "sources": found}, ensure_ascii=False))' "$DS" "$WANT")"

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$RESULT"
else
  printf '%s' "$RESULT" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("Base: " + str(d["datastoreId"]) + "  ·  etiquetas procuradas: " + ", ".join(d["tags"]))
print("Fontes com a(s) etiqueta(s): %d de %d" % (d["matchedSources"], d["totalSources"]))
if not d["sources"]:
    print("")
    print("(nenhuma fonte com essas etiquetas — veja as etiquetas existentes com list-tags.sh)")
else:
    print("")
    print("ID".ljust(30) + "ETIQUETA(s)".ljust(20) + "CUSTOM_ID".ljust(14) + "CHUNKS".ljust(8) + "NOME")
    for s in d["sources"]:
        print(str(s["id"]).ljust(30) + ",".join(s["matched"]).ljust(20)
              + str(s["custom_id"] or "-").ljust(14) + str(s["nbChunks"]).ljust(8) + str(s["name"]))
    print("")
    print("Etiqueta é metadado local: serve para organizar/achar as fontes, não filtra a busca.")
    print("Para segmentar a recuperação use custom_id (filters.custom_ids) — query-verify.sh --custom-id.")
'
fi
