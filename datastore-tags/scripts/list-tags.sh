#!/usr/bin/env bash
# list-tags.sh — agrega as etiquetas (config.tags) de todas as fontes de uma base.
#
# As etiquetas vivem em `config.tags` de cada FONTE (datasource); a base em si
# não tem etiquetas. A API não expõe endpoint de etiquetas: agregamos paginando
# GET /datasources/list. Contrato completo em SOURCES.md §4.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: list-tags.sh <api-key> <datastore-id> [--page-size <N>]

Lista as etiquetas (config.tags) usadas nas fontes da base, com a contagem de
fontes por etiqueta e quais são elas. Pagina GET /datasources/list.

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)
  <datastore-id>     ID da base (sufixo _v3)

Opções:
  --page-size <N>    Itens por página na listagem (padrão 100; máx. 100)
  -h, --help         Mostra esta ajuda

Exemplos:
  list-tags.sh "$CHATVOLT_API_KEY" cmszh5s6q0fbdvapf36roho4y_v3
  CV_JSON=1 list-tags.sh "$CHATVOLT_API_KEY" cmszh5s6q0fbdvapf36roho4y_v3

Saída (CV_JSON=1):
  {"datastoreId","totalSources","taggedSources","untaggedSources",
   "tags":[{"tag","count","sources":[{"id","name","custom_id"}]}],
   "untagged":[{"id","name"}]}

Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
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
[ -n "$DS" ] || { usage >&2; cv_die "informe o <datastore-id>"; }

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
by_tag = {}
untagged = []
for s in srcs:
    cfg = s.get("config") or {}
    tags = [str(t).strip() for t in (cfg.get("tags") or []) if str(t).strip()]
    if not tags:
        untagged.append({"id": s.get("id"), "name": s.get("name")})
        continue
    for t in tags:
        by_tag.setdefault(t, []).append({"id": s.get("id"), "name": s.get("name"),
                                         "custom_id": cfg.get("custom_id") or None})
tags_out = [{"tag": t, "count": len(v), "sources": v}
            for t, v in sorted(by_tag.items(), key=lambda kv: (-len(kv[1]), kv[0]))]
print(json.dumps({"datastoreId": ds, "totalSources": len(srcs),
                  "taggedSources": len(srcs) - len(untagged), "untaggedSources": len(untagged),
                  "tags": tags_out, "untagged": untagged}, ensure_ascii=False))' "$DS")"

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$RESULT"
else
  printf '%s' "$RESULT" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("Base: " + str(d["datastoreId"]))
print("Fontes: %d (%d com etiquetas, %d sem)"
      % (d["totalSources"], d["taggedSources"], d["untaggedSources"]))
if not d["tags"]:
    print("")
    print("Nenhuma etiqueta definida nas fontes desta base.")
    print("Defina com: add-tag.sh <api-key> <datastore-id> <source-id> <etiqueta> --reuse-text")
else:
    print("")
    print("ETIQUETA".ljust(24) + "FONTES".ljust(9) + "FONTES (id — nome)")
    for t in d["tags"]:
        first = t["sources"][0]
        print(t["tag"].ljust(24) + str(t["count"]).ljust(9) + str(first["id"]) + " — " + str(first["name"]))
        for s in t["sources"][1:]:
            print("".ljust(24) + "".ljust(9) + str(s["id"]) + " — " + str(s["name"]))
    print("")
    print("Lembrete: etiqueta é metadado local (a API NÃO filtra por ela).")
    print("Para segmentação com efeito na recuperação use custom_id (set-custom-id.sh)"
          " e prove com query-verify.sh --custom-id.")
if d["untagged"]:
    print("")
    print("Fontes sem etiqueta (%d):" % len(d["untagged"]))
    for s in d["untagged"]:
        print("  " + str(s["id"]) + " — " + str(s["name"]))
'
fi
