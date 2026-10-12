#!/usr/bin/env bash
set -euo pipefail

# chatvolt tools-update — delete-tool.sh
# Remove uma tool: DELETE /agents/{agentId}/tools/{toolId}
# A resposta é `{"success":true,"toolId":"..."}` na raiz.
# O nome é lido da listagem (a API não tem GET individual → 404).

usage() {
  cat <<'EOF'
Uso: delete-tool.sh <api-key> <agent-id> <tool-id>

Mostra a tool (nome/tipo, lidos da listagem) e pede confirmação antes do
DELETE.

Opções:
  -h, --help   Mostra esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_JSON=1           imprime SOMENTE JSON em stdout
  CV_YES=1            pula a confirmação
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplo:
  delete-tool.sh "$KEY" "$AG" tool-1
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
[ "$#" -ge 3 ] || cv_die "argumentos insuficientes (use -h para a ajuda)"

cv_get "/agents/${AGENT_ID}/tools"
DATA=$(cv_unwrap "$CV_RESP")

INFO=$(printf '%s' "$DATA" | python3 -c '
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
            cfg = t.get("config") or {}
            name = cfg.get("name") or t.get("datastoreId") or t.get("formId") or ""
            print("%s\t%s\t%s" % (t.get("type") or "", name, tid))
            break
' "$TOOL_ID")

[ -n "$INFO" ] || cv_die "tool '$TOOL_ID' não encontrada no agente $AGENT_ID (a lista é a única fonte: não existe GET individual)"

TOOL_TYPE=$(printf '%s' "$INFO" | cut -f1)
TOOL_NAME=$(printf '%s' "$INFO" | cut -f2)

cv_warn "Você está prestes a deletar a tool:"
cv_warn "  ID:   ${TOOL_ID}"
cv_warn "  Tipo: ${TOOL_TYPE}"
cv_warn "  Nome: ${TOOL_NAME:-<sem nome>}"

cv_confirm "Confirma a exclusão da tool ${TOOL_ID} do agente ${AGENT_ID}?"

cv_request DELETE "/agents/${AGENT_ID}/tools/${TOOL_ID}"

OK=$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("0"); raise SystemExit
print("1" if isinstance(d, dict) and d.get("success") is True else "0")
')

[ "$OK" = "1" ] || cv_die "a API respondeu sem success=true: $(cv_err_msg "$CV_RESP")"

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$CV_RESP"
  exit 0
fi

printf '✅ Tool %s (%s) deletada do agente %s.\n' "$TOOL_ID" "${TOOL_NAME:-$TOOL_TYPE}" "$AGENT_ID"
printf '%s' "$CV_RESP" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))'
