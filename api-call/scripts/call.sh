#!/usr/bin/env bash
# call.sh — chamador genérico da API Chatvolt para QUALQUER endpoint.
#
# Cobre os 136 endpoints documentados (ver data/endpoints.json) e qualquer rota
# nova: monta a requisição, trata 401/402/403/404/406/429/5xx e desembrulha o
# envelope quando existir. Use --raw/--stream/--out para respostas especiais.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: call.sh <api-key> <MÉTODO> <caminho> [opções]
     call.sh <api-key> --catalog [--group <g>] [--filter <regex>]

MÉTODO        GET | POST | PUT | PATCH | DELETE
caminho       caminho da API, começando com / (ex.: /agents/{id}/tools)

Opções:
  --json '<json>'      corpo JSON enviado como está
  --data-file <arq>    corpo JSON lido de um arquivo (use - para stdin)
  --form <k=v>         corpo urlencoded (repetível)
  --query <k=v>        parâmetro de query (repetível; valores são escapados)
  --unwrap             aplica d.data quando a resposta é {data: ...} (padrão já faz isso)
  --no-unwrap          imprime a resposta crua sem desembrulhar
  --raw                imprime o corpo exatamente como veio (sem formatar JSON)
  --stream             mantém a conexão aberta (SSE; ex.: /crm/events) até Ctrl+C
  --out <arquivo>      salva a resposta em arquivo (use em respostas binárias, ex.: export)
  --all                pagina automaticamente quando a resposta trouxer pagination.offset/limit
  --max-time <s>       timeout do curl (padrão 120; 0 = sem limite)
  -h, --help           mostra esta ajuda

Exemplos:
  call.sh "$CHATVOLT_API_KEY" GET /agents
  call.sh "$CHATVOLT_API_KEY" GET /conversation --query agentId="$AGENT" --query limit=5
  call.sh "$CHATVOLT_API_KEY" POST /agents/"$AGENT"/query --json '{"query":"oi"}'
  call.sh "$CHATVOLT_API_KEY" GET /crm/events --query scenarioId="$SC" --stream
  call.sh "$CHATVOLT_API_KEY" GET /conversations/"$CONV"/export --out conversa.zip

Ambiente: CHATVOLT_API_KEY · CV_API_BASE · CV_JSON=1 (stdout só JSON)
Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift

if [ "${1:-}" = "--catalog" ]; then
  shift
  exec "$(dirname "$0")/catalog.sh" "$@"
fi

METHOD="${1:-}"; shift || true
PATH_ARG="${1:-}"; shift || true
[ -n "$METHOD" ] || { usage >&2; cv_die "informe o método HTTP"; }
[ -n "$PATH_ARG" ] || { usage >&2; cv_die "informe o caminho da API"; }
case "$PATH_ARG" in /*) ;; *) cv_die "o caminho deve começar com / (recebido: $PATH_ARG)" ;; esac

BODY=""; BODY_FILE=""; NO_UNWRAP=0; RAW=0; STREAM=0; OUT=""; ALL=0
QUERY=(); FORMS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --json)      [ -n "${2:-}" ] || cv_die "--json exige o corpo"; BODY="$2"; shift 2 ;;
    --data-file) [ -n "${2:-}" ] || cv_die "--data-file exige o arquivo"; BODY_FILE="$2"; shift 2 ;;
    --form)      [ -n "${2:-}" ] || cv_die "--form exige k=v"; FORMS+=("$2"); shift 2 ;;
    --query)     [ -n "${2:-}" ] || cv_die "--query exige k=v"; QUERY+=("$2"); shift 2 ;;
    --unwrap)    NO_UNWRAP=0; shift ;;
    --no-unwrap) NO_UNWRAP=1; shift ;;
    --raw)       RAW=1; shift ;;
    --stream)    STREAM=1; shift ;;
    --out)       [ -n "${2:-}" ] || cv_die "--out exige o arquivo"; OUT="$2"; shift 2 ;;
    --all)       ALL=1; shift ;;
    --max-time)  [ -n "${2:-}" ] || cv_die "--max-time exige segundos"; export CV_TIMEOUT="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

if [ -n "$BODY_FILE" ]; then
  if [ "$BODY_FILE" = "-" ]; then BODY="$(cat)"; else BODY="$(cat -- "$BODY_FILE")"; fi
fi
[ -z "$BODY" ] || [ -z "${FORMS[*]:-}" ] || cv_die "use --json/--data-file OU --form, não os dois"
[ -z "$BODY" ] || python3 -c 'import json,sys; json.loads(sys.argv[1])' "$BODY" 2>/dev/null || cv_die "--json/--data-file precisa ser JSON válido"

# Monta a query string com escape correto (sem interpolar valores em shell).
FULL_PATH="$PATH_ARG"
if [ "${#QUERY[@]}" -gt 0 ]; then
  QS=$(python3 - "${QUERY[@]}" <<'PY'
import sys, urllib.parse
pairs = []
for item in sys.argv[1:]:
    if "=" not in item:
        raise SystemExit(f"--query exige k=v (recebido: {item})")
    k, v = item.split("=", 1)
    pairs.append((k, v))
print(urllib.parse.urlencode(pairs))
PY
)
  case "$FULL_PATH" in *\?*) FULL_PATH="${FULL_PATH}&${QS}" ;; *) FULL_PATH="${FULL_PATH}?${QS}" ;; esac
fi

# Corpo urlencoded, se pedido.
if [ "${#FORMS[@]}" -gt 0 ]; then
  BODY=$(python3 - "${FORMS[@]}" <<'PY'
import sys, urllib.parse, json
print(json.dumps({k: v for k, v in (i.split("=", 1) for i in sys.argv[1:])}))
PY
)
  cv_warn "--form: enviando como JSON equivalente (a API do Chatvolt usa JSON em todos os endpoints documentados)"
fi

EXEC_URL="${CV_BASE_URL}${FULL_PATH}"

# ── modos especiais que não passam pelo cv_request ─────────────────────────
if [ -n "$OUT" ]; then
  curl -sS --max-time "${CV_TIMEOUT:-120}" -o "$OUT" -w '%{http_code} %{content_type} %{size_download}\n' \
    -X "$METHOD" -H "Authorization: Bearer ${API_KEY}" \
    ${BODY:+-H 'Content-Type: application/json' --data-binary "$BODY"} "$EXEC_URL" >/tmp/cv-call-out.txt || cv_die "falha ao baixar $FULL_PATH" 4
  cv_info "salvo em ${OUT}: $(cat /tmp/cv-call-out.txt)"
  exit 0
fi

if [ "$STREAM" = "1" ]; then
  cv_warn "streaming (Ctrl+C para encerrar)…"
  exec curl -sS -N --max-time "${CV_TIMEOUT:-120}" -X "$METHOD" \
    -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
    ${BODY:+--data-binary "$BODY"} "$EXEC_URL"
fi

if [ "$ALL" = "1" ]; then
  TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
  : > "$TMPD/items.jsonl"
  OFFSET=0; PAGE=0
  while :; do
    PAGE=$((PAGE + 1))
    case "$FULL_PATH" in *\?*) SEP="&" ;; *) SEP="?" ;; esac
    cv_request "$METHOD" "${FULL_PATH}${SEP}offset=${OFFSET}" "$BODY"
    printf '%s' "$CV_RESP" >> "$TMPD/pages.jsonl"
    printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    items = d.get("data")
    if items is None:  # {contacts:[…]}, {lists:[…]}, {dispatches:[…]} — primeira lista do objeto
        items = next((v for v in d.values() if isinstance(v, list)), [])
else:
    items = d
for it in (items or []):
    print(json.dumps(it, ensure_ascii=False))' >> "$TMPD/items.jsonl"
    NEXT=$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    items = d.get("data")
    if items is None and "pagination" in d:
        items = next((v for v in d.values() if isinstance(v, list)), [])
else:
    items = d
items = items or []
p = (d.get("pagination") or {}) if isinstance(d, dict) else {}
if not items or p.get("total") is None:
    print(""); raise SystemExit
done_n = (p.get("offset") or 0) + len(items)
print("" if done_n >= (p.get("total") or 0) else done_n)')
    [ -n "$NEXT" ] || break
    OFFSET="$NEXT"
    if [ "$PAGE" -ge 200 ]; then cv_warn "parando em 200 páginas (use o cursor manualmente)"; break; fi
    sleep 0.3
  done
  AGG=$(python3 -c '
import json, sys
out = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
print(json.dumps(out, ensure_ascii=False))' "$TMPD/items.jsonl")
  cv_emit "$AGG"
  cv_info "coleção: $(wc -l < "$TMPD/items.jsonl") item(ns) em ${PAGE} página(s)"
  exit 0
fi

cv_request "$METHOD" "$FULL_PATH" "$BODY"

if [ "$RAW" = "1" ]; then
  printf '%s\n' "$CV_RESP"
  exit 0
fi
if [ "$NO_UNWRAP" = "1" ]; then
  cv_emit "$CV_RESP"
  exit 0
fi

cv_emit "$(cv_unwrap "$CV_RESP")"
