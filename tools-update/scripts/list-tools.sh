#!/usr/bin/env bash
set -euo pipefail

# chatvolt tools-update — list-tools.sh
# Lista (e busca) as ferramentas (tools) configuradas em um agente.
#
# A API NÃO tem GET individual por tool: GET /agents/{agentId}/tools/{toolId}
# responde 404. Para "ver uma tool", filtre esta lista com --id.

usage() {
  cat <<'EOF'
Uso: list-tools.sh <api-key> <agent-id> [opções]

Lista as tools de um agente Chatvolt em tabela.

Opções:
  --type <T>   Filtra por tipo (http, datastore, form, quick_reply_buttons, ...)
  --id <ID>    Mostra apenas a tool com este id. É o único jeito de "ver uma
               tool" — a API não expõe GET individual (retorna 404).
  --full       Despeja o JSON completo (filtrado) em vez da tabela.
  -h, --help   Mostra esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_JSON=1           imprime SOMENTE JSON em stdout
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Colunas da tabela: id, type, name, detail (url/datastoreId/formId), isRaw,
hasMaximumToolCalls, maximumToolCalls.

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplos:
  list-tools.sh "$KEY" cmt8mfhzv00h2g9gtypyp54l1
  list-tools.sh "$KEY" "$AG" --type http
  list-tools.sh "$KEY" "$AG" --id cmupjsf7d0351v1pd9t7idyiv --full
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
AGENT_ID="${2:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id como 2º argumento ou exporte CHATVOLT_AGENT_ID"
if [ "$#" -ge 2 ]; then shift 2; elif [ "$#" -ge 1 ]; then shift 1; fi

TYPE_FILTER=""
ID_FILTER=""
FULL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --type) [ -n "${2:-}" ] || cv_die "--type exige um valor"; TYPE_FILTER="$2"; shift 2 ;;
    --id)   [ -n "${2:-}" ] || cv_die "--id exige um valor";   ID_FILTER="$2";   shift 2 ;;
    --full) FULL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

cv_get "/agents/${AGENT_ID}/tools"
DATA=$(cv_unwrap "$CV_RESP")

TOOLS=$(printf '%s' "$DATA" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    for k in ("tools", "data", "results"):
        if isinstance(d.get(k), list):
            d = d[k]
            break
if not isinstance(d, list):
    print("[]")
    raise SystemExit
print(json.dumps(d, ensure_ascii=False))
')

FILTERED=$(printf '%s' "$TOOLS" | python3 -c '
import json, sys
tools = json.load(sys.stdin)
tf, idf = sys.argv[1], sys.argv[2]
out = [t for t in tools
       if (not tf or t.get("type") == tf) and (not idf or t.get("id") == idf)]
print(json.dumps(out, ensure_ascii=False))
' "$TYPE_FILTER" "$ID_FILTER")

COUNT=$(printf '%s' "$FILTERED" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')

if [ "$COUNT" = "0" ]; then
  if [ -n "$ID_FILTER" ]; then
    cv_die "tool '$ID_FILTER' não encontrada no agente $AGENT_ID (a API não expõe GET individual: /agents/{id}/tools/{toolId} responde 404 — use a lista)"
  fi
  if [ -n "$TYPE_FILTER" ]; then
    cv_info "Nenhuma tool do tipo '$TYPE_FILTER' no agente $AGENT_ID."
  else
    cv_info "Nenhuma tool configurada no agente $AGENT_ID."
  fi
  exit 0
fi

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$FILTERED"
  exit 0
fi

if [ "$FULL" = "1" ]; then
  printf '%s' "$FILTERED" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))'
  exit 0
fi

FORMATTER='
import json, sys
tools = json.load(sys.stdin)

def fields(t):
    cfg = t.get("config") or {}
    typ = t.get("type") or ""
    name = cfg.get("name") or ""
    if typ == "datastore":
        detail = t.get("datastoreId") or ""
    elif typ == "form":
        detail = t.get("formId") or ""
    else:
        detail = cfg.get("url") or ""
        if cfg.get("mode"):
            detail = (detail + " " if detail else "") + "mode=" + str(cfg.get("mode"))
    if not name:
        name = typ
    maxc = cfg.get("maximumToolCalls")
    if maxc is None:
        maxc = t.get("maximumToolCalls")
    raw = t.get("isRaw") or cfg.get("isRaw")
    hasmax = cfg.get("hasMaximumToolCalls") or t.get("hasMaximumToolCalls")
    return [
        str(t.get("id") or ""),
        typ,
        name,
        detail,
        "sim" if raw else "-",
        "sim" if hasmax else "-",
        "-" if maxc is None else str(maxc),
    ]

header = ["ID", "TYPE", "NAME", "DETAIL (url/datastoreId/formId)", "isRaw", "hasMax", "maxCalls"]
rows = [fields(t) for t in tools]
widths = [len(h) for h in header]
for r in rows:
    for i, c in enumerate(r):
        widths[i] = max(widths[i], len(c))

def line(cols):
    return "  ".join(c.ljust(widths[i]) for i, c in enumerate(cols)).rstrip()

print(line(header))
print("  ".join("-" * w for w in widths))
for r in rows:
    print(line(r))
print()
print("Total: %d tool(s)" % len(rows))
'

printf '%s' "$FILTERED" | python3 -c "$FORMATTER"
