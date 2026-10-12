#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — set-priority
#
# Muda a prioridade de uma conversa: LOW, MEDIUM ou HIGH.
#
# Uso:
#   set-priority.sh [api-key] <conversation-id> <priority> [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
set-priority.sh — define a prioridade de uma conversa do Chatvolt

Uso:
  set-priority.sh [api-key] <conversation-id> <LOW|MEDIUM|HIGH> [--yes]

Argumentos:
  <conversation-id>  id da conversa
  <priority>         LOW | MEDIUM | HIGH (aceita minúsculas)

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
PRIORITY=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)     CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift
               elif [ -z "$PRIORITY" ]; then PRIORITY="$1"; shift
               else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }
[ -n "$PRIORITY" ] || { usage >&2; cv_die "informe a <priority> (LOW, MEDIUM ou HIGH)"; }

PRIORITY=$(printf '%s' "$PRIORITY" | tr '[:lower:]' '[:upper:]')
case "$PRIORITY" in
  LOW|MEDIUM|HIGH) ;;
  *) cv_die "prioridade inválida: '$PRIORITY' — use LOW, MEDIUM ou HIGH" ;;
esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

BODY=$(python3 - "$PRIORITY" <<'PY'
import json, sys
print(json.dumps({"priority": sys.argv[1]}, ensure_ascii=False))
PY
)

cv_confirm "Mudar a prioridade da conversa ${CONV_ID} para ${PRIORITY}?"

cv_request POST "/conversations/${CONV_ID}/set-priority" "$BODY"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    print("OK:", d.get("message") or d.get("success"))
else:
    print(d)'
