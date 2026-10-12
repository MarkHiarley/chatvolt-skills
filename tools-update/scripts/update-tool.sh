#!/usr/bin/env bash
set -euo pipefail

# chatvolt tools-update — update-tool.sh
# Atualiza uma tool: PATCH /agents/{agentId}/tools/{toolId}.
#
# O corpo do PATCH exige o discriminador `type` — se o JSON informado não
# trouxer `type`, o script injeta o `type` atual da tool.
# O estado atual é lido da listagem (a API não tem GET individual → 404).

usage() {
  cat <<'EOF'
Uso: update-tool.sh <api-key> <agent-id> <tool-id> <json|--file <path>>

Mostra o estado atual da tool (via listagem), o diff e pede confirmação
antes de aplicar o PATCH.

Opções:
  --file <path>   Lê o JSON do corpo de um arquivo.
  -h, --help      Mostra esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_JSON=1           imprime SOMENTE JSON em stdout
  CV_YES=1            pula a confirmação
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplo:
  update-tool.sh "$KEY" "$AG" tool-1 '{"type":"http","config":{"name":"Status","description":"Consulta status","url":"https://api.exemplo.com/status","method":"GET","hasMaximumToolCalls":true,"maximumToolCalls":2}}'
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
AGENT_ID="${2:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id como 2º argumento ou exporte CHATVOLT_AGENT_ID"
TOOL_ID="${3:-}"
[ -n "$TOOL_ID" ] || cv_die "informe o tool-id como 3º argumento"
[ "$#" -ge 3 ] || cv_die "informe o JSON do corpo (use -h para a ajuda)"
shift 3

PAYLOAD=""
FILE=""
case "${1:-}" in
  --file) [ -n "${2:-}" ] || cv_die "--file exige um caminho"; FILE="$2"; shift 2 ;;
  "") : ;;
  *) PAYLOAD="$1"; shift 1 ;;
esac
[ "$#" -eq 0 ] || cv_die "argumentos extras inesperados: $*"

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || cv_die "arquivo não encontrado: $FILE"
  NEW_RAW=$(cat "$FILE")
else
  [ -n "$PAYLOAD" ] || cv_die "informe o JSON do corpo: <json> | --file <path>"
  NEW_RAW="$PAYLOAD"
fi

cv_get "/agents/${AGENT_ID}/tools"
DATA=$(cv_unwrap "$CV_RESP")

CUR=$(printf '%s' "$DATA" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    for k in ("tools", "data", "results"):
        if isinstance(d.get(k), list):
            d = d[k]
            break
tid = sys.argv[1]
if isinstance(d, list):
    for t in d:
        if t.get("id") == tid:
            print(json.dumps(t, ensure_ascii=False))
            break
' "$TOOL_ID")

[ -n "$CUR" ] || cv_die "tool '$TOOL_ID' não encontrada no agente $AGENT_ID (a lista é a única fonte: não existe GET individual)"

NEW=$(python3 - "$NEW_RAW" "$CUR" <<'PY'
import json, sys
try:
    new = json.loads(sys.argv[1])
except Exception as e:
    raise SystemExit("JSON inválido: %s" % e)
if not isinstance(new, dict):
    raise SystemExit("o corpo deve ser um objeto JSON")
cur = json.loads(sys.argv[2])
if not new.get("type") and isinstance(cur, dict) and cur.get("type"):
    new["type"] = cur["type"]
    print("AVISO: 'type' ausente — injetado do estado atual ('%s')" % cur["type"], file=sys.stderr)
print(json.dumps(new, ensure_ascii=False))
PY
)

{
  echo "Estado atual da tool ${TOOL_ID}:"
  printf '%s' "$CUR" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))'
  echo
  echo "Diff (atual → novo):"
  python3 - "$CUR" "$NEW" <<'PY'
import json, sys, difflib
a = json.dumps(json.loads(sys.argv[1]), indent=2, ensure_ascii=False, sort_keys=True).splitlines()
b = json.dumps(json.loads(sys.argv[2]), indent=2, ensure_ascii=False, sort_keys=True).splitlines()
lines = list(difflib.unified_diff(a, b, "atual", "novo", lineterm=""))
print("\n".join(lines) if lines else "(sem diferenças)")
PY
} >&2

cv_confirm "Aplicar PATCH na tool ${TOOL_ID} do agente ${AGENT_ID}?"

cv_request PATCH "/agents/${AGENT_ID}/tools/${TOOL_ID}" "$NEW"

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$CV_RESP"
  exit 0
fi

printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("✅ Tool atualizada.")
print()
print(json.dumps(d, indent=2, ensure_ascii=False))
'
