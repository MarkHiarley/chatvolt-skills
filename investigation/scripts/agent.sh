#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Investigation: detalhes completos de um agente.
# Uso: agent.sh <api-key|--> <agent-id>
# A API key também pode vir de CHATVOLT_API_KEY; o id de CHATVOLT_AGENT_ID.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: agent.sh <api-key> <agent-id>

Busca o objeto completo do agente (GET /agents/{id}) e imprime como JSON
formatado. Em modo CV_JSON=1 imprime o JSON cru (uma linha) em stdout.

Argumentos:
  <api-key>   API key do Chatvolt (ou use a variável CHATVOLT_API_KEY)
  <agent-id>  ID do agente (ou use a variável CHATVOLT_AGENT_ID)

Opções:
  -h, --help  mostra esta ajuda

Exemplos:
  agent.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1
  CV_JSON=1 agent.sh "" cmt8mfhzv00h2g9gtypyp54l1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["modelName"])'

Variáveis:
  CV_API_BASE   base URL alternativa (padrão https://api.chatvolt.ai)
  CV_JSON=1     imprime somente JSON em stdout (diagnósticos em stderr)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
AGENT_ID="${2:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o ID do agente como 2o argumento ou exporte CHATVOLT_AGENT_ID"

cv_get "/agents/${AGENT_ID}"
PAYLOAD=$(cv_unwrap "$CV_RESP")
cv_emit "$PAYLOAD"
