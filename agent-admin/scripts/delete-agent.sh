#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — delete-agent
#
# Deleta um agente (DELETE /agents/{id}). O agente é lido antes (somente leitura)
# para mostrar o nome, e a exclusão exige confirmação (CV_YES=1 pula em testes).
# ATENÇÃO: a API remove também os dados associados (service providers, permissões).
#
# Uso:
#   delete-agent.sh [api-key] <agent-id> [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1          pula a confirmação interativa
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
delete-agent.sh — deleta um agente do Chatvolt

Uso:
  delete-agent.sh [api-key] <agent-id> [--yes]

Argumentos:
  <agent-id>   id do agente a deletar

Opções:
  --yes        pula a confirmação interativa
  -h, --help   mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY  API key (alternativa ao 1º argumento)
  CV_JSON=1         imprime somente JSON em stdout
  CV_YES=1          pula a confirmação interativa
  CV_API_BASE       base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

AGENT_ID=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)     export CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$AGENT_ID" ]; then AGENT_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$AGENT_ID" ] || { usage >&2; cv_die "informe o id do agente a deletar"; }

API_KEY=$(cv_req_key "$API_KEY_ARG")

# 1) Lê o agente (somente leitura) para exibir o que será apagado.
cv_get "/agents/${AGENT_ID}"
OBJ=$(cv_unwrap "$CV_RESP")

SUMMARY=$(printf '%s' "$OBJ" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print("(resposta inesperada da API)"); raise SystemExit
print("  id:           " + str(d.get("id", "")))
print("  nome:         " + str(d.get("name", "")))
print("  descrição:    " + str(d.get("description", "") or "-"))
print("  modelo:       " + str(d.get("modelName", "") or "-"))
')

cv_info "Agente encontrado:"
cv_info "$SUMMARY"
cv_info ""
cv_warn "deletar remove o agente E seus dados associados (permissões, service providers)."

cv_confirm "Deletar definitivamente o agente ${AGENT_ID}?"

cv_request DELETE "/agents/${AGENT_ID}"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("Agente %s deletado (%s)." % (d.get("id", ""), d.get("name", "")))
else:
    print("Resposta: " + json.dumps(d, ensure_ascii=False))
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
