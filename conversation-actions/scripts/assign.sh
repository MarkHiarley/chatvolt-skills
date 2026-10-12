#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — assign
#
# Atribui uma conversa a um atendente (usuário da organização). O atendente
# pode ser identificado por e-mail, id de usuário ou id de membership.
#
# Uso:
#   assign.sh [api-key] <conversation-id> (--email <e> | --id <user-id> | --membership-id <m>) [--force] [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
assign.sh — atribui uma conversa do Chatvolt a um atendente

Uso:
  assign.sh [api-key] <conversation-id> (--email <e> | --id <user-id> | --membership-id <id>)
            [--force] [--yes]

Argumentos:
  <conversation-id>    id da conversa

Opções (informe exatamente UMA das três):
  --email <e>          e-mail do usuário que receberá a conversa
  --id <user-id>       id do usuário
  --membership-id <m>  id do membership
  --force              reatribui mesmo se a conversa já estiver com outro
                       atendente (sem isto a API responde 409 Conflict)
  --yes                não pede confirmação
  -h, --help           mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY     API key (alternativa ao 1º argumento)
  CV_JSON=1            imprime somente JSON em stdout
  CV_YES=1             pula a confirmação interativa
  CV_API_BASE          base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
EMAIL=""
USER_ID=""
MEMBERSHIP_ID=""
FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --email)         [ -n "${2:-}" ] || cv_die "--email exige um valor"; EMAIL="$2"; shift 2 ;;
    --id)            [ -n "${2:-}" ] || cv_die "--id exige um valor"; USER_ID="$2"; shift 2 ;;
    --membership-id) [ -n "${2:-}" ] || cv_die "--membership-id exige um valor"; MEMBERSHIP_ID="$2"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    --yes)           CV_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              cv_die "opção desconhecida: $1 (use --help)" ;;
    *)               if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }

TARGETS=0
for v in "$EMAIL" "$USER_ID" "$MEMBERSHIP_ID"; do
  [ -n "$v" ] && TARGETS=$((TARGETS + 1))
done
[ "$TARGETS" -eq 1 ] || cv_die "informe exatamente um destinatário: --email <e>, --id <user-id> ou --membership-id <id>"

API_KEY=$(cv_req_key "$API_KEY_ARG")

BODY=$(python3 - "$EMAIL" "$USER_ID" "$MEMBERSHIP_ID" "$FORCE" <<'PY'
import json, sys
email, user_id, membership_id, force = sys.argv[1:5]
b = {}
if email:
    b["email"] = email
elif user_id:
    b["id"] = user_id
else:
    b["membershipId"] = membership_id
if force == "1":
    b["force"] = True
print(json.dumps(b, ensure_ascii=False))
PY
)

WHO="${EMAIL:-${USER_ID:-$MEMBERSHIP_ID}}"
cv_confirm "Atribuir a conversa ${CONV_ID} para ${WHO}?"

cv_request POST "/conversations/${CONV_ID}/assign" "$BODY"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    print("OK:", d.get("message") or d.get("success"))
else:
    print(d)'
