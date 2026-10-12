#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — list-agents
#
# Lista os agentes da organização (GET /agents). A resposta é um ARRAY na raiz
# (sem envelope {data:...}), verificado ao vivo em 2026-10-12.
#
# Uso:
#   list-agents.sh [api-key] [--filter <regex>] [--limit <n>]
#
# Opções:
#   --filter <regex>  mostra só agentes cujo nome, id ou handle casem com o regex
#   --limit <n>       limita a quantidade de linhas exibidas
#   -h, --help        mostra esta ajuda
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
list-agents.sh — lista os agentes da organização

Uso:
  list-agents.sh [api-key] [--filter <regex>] [--limit <n>]

Opções:
  --filter <regex>  filtra por nome, id ou handle (case-insensitive)
  --limit <n>       limita o número de agentes exibidos
  -h, --help        mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY  API key (alternativa ao 1º argumento)
  CV_JSON=1         imprime somente JSON em stdout
  CV_API_BASE       base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

FILTER=""
LIMIT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --filter)  [ "$#" -ge 2 ] || cv_die "--filter exige um valor"; FILTER="$2"; shift 2 ;;
    --limit)   [ "$#" -ge 2 ] || cv_die "--limit exige um valor"; LIMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         cv_die "argumento extra: $1" ;;
  esac
done

if [ -n "$LIMIT" ]; then
  case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um inteiro positivo" ;; esac
  [ "$LIMIT" -ge 1 ] || cv_die "--limit deve ser >= 1"
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

cv_get "/agents"
RAW=$(cv_unwrap "$CV_RESP")

# Filtro/limite são aplicados antes da formatação; os valores entram por
# sys.argv (nunca interpolados no código Python).
if [ -n "$FILTER" ] || [ -n "$LIMIT" ]; then
  RAW=$(printf '%s' "$RAW" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
flt = sys.argv[1]
lim = int(sys.argv[2]) if sys.argv[2] else 0
if not isinstance(d, list):
    print(json.dumps(d, ensure_ascii=False)); raise SystemExit
rx = re.compile(flt, re.I) if flt else None
rows = []
for a in d:
    if not isinstance(a, dict):
        continue
    if rx:
        blob = " ".join(str(a.get(k) or "") for k in ("name", "id", "handle"))
        if not rx.search(blob):
            continue
    rows.append(a)
if lim:
    rows = rows[:lim]
print(json.dumps(rows, ensure_ascii=False))
' "$FILTER" "$LIMIT")
fi

FORMATTER='
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, list):
    print("(resposta inesperada: esperava um array de agentes)")
    raise SystemExit
hdr = "%-26s %-28s %-18s %-8s %s"
print(hdr % ("ID", "NOME", "MODELO", "VISIB.", "HANDLE"))
for a in d:
    if not isinstance(a, dict):
        continue
    print(hdr % (
        str(a.get("id", ""))[:26],
        str(a.get("name", ""))[:28],
        str(a.get("modelName") or "-")[:18],
        str(a.get("visibility") or "-")[:8],
        a.get("handle") or "-",
    ))
print("\nTotal: %d" % len(d))
'

cv_emit "$RAW" "$FORMATTER"
