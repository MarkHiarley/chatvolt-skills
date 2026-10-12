#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — unassign
#
# Remove o atendente atualmente atribuído a uma conversa.
#
# Uso:
#   unassign.sh [api-key] <conversation-id> [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
unassign.sh — desatribui o atendente de uma conversa do Chatvolt

Uso:
  unassign.sh [api-key] <conversation-id> [--yes]

Argumentos:
  <conversation-id>  id da conversa que ficará sem atendente

Opções:
  --yes              não pede confirmação
  -h, --help         mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY   API key (alternativa ao 1º argumento)
  CV_JSON=1          imprime somente JSON em stdout
  CV_YES=1           pula a confirmação interativa
  CV_API_BASE        base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)     CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }

API_KEY=$(cv_req_key "$API_KEY_ARG")

cv_confirm "Remover o atendente responsável pela conversa ${CONV_ID}?"

cv_request POST "/conversations/${CONV_ID}/unassign"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    print("OK:", d.get("message") or d.get("success"))
else:
    print(d)'
