#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — history
#
# Histórico de conversas da organização, filtrado por e-mail de contato e
# agente. Os dois filtros são OBRIGATÓRIOS: sem eles a API responde
# 400 'Invalid request body (validation failed)' com
# {"email":{"Required"},"agentId":{...}}.
#
# Uso:
#   history.sh [api-key] --email <e> --agent-id <id> [--limit N] [--cursor <c>]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
history.sh — histórico de conversas do Chatvolt (por e-mail de contato + agente)

Uso:
  history.sh [api-key] --email <e-mail> --agent-id <id> [--limit N] [--cursor <token>]

Opções:
  --email <e-mail>    e-mail do contato (obrigatório — a API exige)
  --agent-id <id>     id do agente (obrigatório — a API exige)
  --limit <n>         máximo de conversas por página
  --cursor <token>    continua a partir do nextCursor da página anterior
  -h, --help          mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Endpoint: GET /conversations/history?email=...&agentId=...
Os filtros vão na QUERY STRING (enviá-los no corpo devolve 400). Resposta:
{"conversations":[...],"nextCursor":<token|null>,"email":"...","agentId":"..."}.

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

EMAIL=""
AGENT_ID=""
LIMIT=""
CURSOR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --email)    [ -n "${2:-}" ] || cv_die "--email exige um endereço"; EMAIL="$2"; shift 2 ;;
    --agent-id) [ -n "${2:-}" ] || cv_die "--agent-id exige um id"; AGENT_ID="$2"; shift 2 ;;
    --limit)    [ -n "${2:-}" ] || cv_die "--limit exige um número"; LIMIT="$2"; shift 2 ;;
    --cursor)   [ -n "${2:-}" ] || cv_die "--cursor exige o token"; CURSOR="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         cv_die "opção desconhecida: $1 (use --help)" ;;
    *)          cv_die "argumento extra: $1 (use --email e --agent-id)" ;;
  esac
done

[ -n "$EMAIL" ] || { usage >&2; cv_die "informe --email <e-mail> do contato (a API exige este filtro)"; }
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "informe --agent-id <id> (a API exige este filtro)"; }

if [ -n "$LIMIT" ]; then
  case "$LIMIT" in
    ''|*[!0-9]*) cv_die "--limit deve ser um número inteiro (recebido: '$LIMIT')" ;;
  esac
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

QS=$(python3 - "$EMAIL" "$AGENT_ID" "$LIMIT" "$CURSOR" <<'PY'
import sys, urllib.parse
email, agent_id, limit, cursor = sys.argv[1:5]
params = {"email": email, "agentId": agent_id}
if limit:
    params["limit"] = limit
if cursor:
    params["cursor"] = cursor
print(urllib.parse.urlencode(params))
PY
)

cv_get "/conversations/history?${QS}"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict) and isinstance(d.get("conversations"), list):
    convs = d["conversations"]
    print("conversas: %d | próximo cursor: %s" % (len(convs), d.get("nextCursor") or "-"))
    for c in convs:
        print("%s | %s | %s | %s" % (c.get("id", "?"), c.get("channel", "?"), c.get("status", "?"),
                                     (c.get("createdAt") or "")[:19].replace("T", " ")))
else:
    print(json.dumps(d, ensure_ascii=False, indent=2))'
