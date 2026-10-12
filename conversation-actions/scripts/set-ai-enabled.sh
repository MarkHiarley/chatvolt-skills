#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — set-ai-enabled
#
# Liga/desliga a IA em uma conversa. Com a IA desligada o agente para de
# responder e a conversa fica para atendimento humano.
#
# Uso:
#   set-ai-enabled.sh [api-key] <conversation-id> <on|off> [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
set-ai-enabled.sh — liga/desliga a IA em uma conversa do Chatvolt

Uso:
  set-ai-enabled.sh [api-key] <conversation-id> <on|off> [--yes]

Argumentos:
  <conversation-id>  id da conversa
  <on|off>           estado desejado da IA (aceita true/false/enabled/disabled)

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
STATE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --on)      STATE=on; shift ;;
    --off)     STATE=off; shift ;;
    --yes)     CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift
               elif [ -z "$STATE" ]; then STATE="$1"; shift
               else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }
[ -n "$STATE" ] || { usage >&2; cv_die "informe o estado da IA (on ou off)"; }

STATE=$(printf '%s' "$STATE" | tr '[:upper:]' '[:lower:]')
case "$STATE" in
  on|true|enabled|enable|1)  ENABLED=true ;;
  off|false|disabled|disable|0) ENABLED=false ;;
  *) cv_die "estado inválido: '$STATE' — use on ou off" ;;
esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

BODY=$(python3 - "$ENABLED" <<'PY'
import json, sys
print(json.dumps({"enabled": sys.argv[1] == "true"}))
PY
)

if [ "$ENABLED" = "true" ]; then AI_TXT="LIGAR"; else AI_TXT="DESLIGAR"; fi
cv_confirm "${AI_TXT} a IA da conversa ${CONV_ID}?"

cv_request POST "/conversations/${CONV_ID}/set-ai-enabled" "$BODY"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    print("OK:", d.get("message") or d.get("success"))
else:
    print(d)'
