#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — delete-conversation
#
# Deleta UMA conversa. Por segurança, recusa canais que não sejam "api"
# (conversas de teste) a menos que --force seja usado explicitamente.
#
# Uso:
#   delete-conversation.sh [api-key] <conversation-id> [--force]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
delete-conversation.sh — deleta uma conversa do Chatvolt

Uso:
  delete-conversation.sh [api-key] <conversation-id> [--force]

Argumentos:
  <conversation-id>   id da conversa a deletar

Opções:
  --force             permite deletar conversas de canais reais
                      (whatsapp, slack, messenger, email, ...).
                      SEM --force só o canal "api" é aceito.
  -h, --help          mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_YES=1            pula a confirmação interativa
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
# 1º argumento posicional = api-key (vence o CHATVOLT_API_KEY do ambiente,
# igual às outras skills); a env var é só o atalho quando ele é omitido.
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o id da conversa"; }

API_KEY=$(cv_req_key "$API_KEY_ARG")

# 1) Busca o objeto da conversa (somente leitura) para saber o canal.
cv_get "/conversation/${CONV_ID}"
OBJ=$(cv_unwrap "$CV_RESP")

if printf '%s' "$OBJ" | grep -q '^null$'; then
  cv_die "conversa não encontrada: ${CONV_ID}"
fi

SUMMARY=$(printf '%s' "$OBJ" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print("(resposta inesperada da API)")
    raise SystemExit
cs = d.get("participantsContacts") or []
name = "-"
if cs:
    name = cs[0].get("firstName") or cs[0].get("email") or cs[0].get("phoneNumber") or "-"
created = (d.get("createdAt") or "")[:16].replace("T", " ")
print("id:      " + str(d.get("id", "")))
print("canal:   " + str(d.get("channel", "?")))
print("status:  " + str(d.get("status", "?")))
print("agente:  " + str(d.get("agentId", "-")))
print("criada:  " + created)
print(f"contato: {name}")
')

CHANNEL=$(printf '%s' "$OBJ" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get("channel", "") if isinstance(d, dict) else "")
except Exception:
    print("")')

cv_info "Conversa encontrada:"
cv_info "$SUMMARY"
cv_info ""

if [ "$CHANNEL" != "api" ] && [ "$FORCE" != "1" ]; then
  cv_warn "canal da conversa: '${CHANNEL:-desconhecido}'"
  cv_die "recusando deletar uma conversa de canal diferente de 'api'. Conversas reais (whatsapp, slack, e-mail...) NÃO devem ser apagadas por engano. Use --force apenas se tiver certeza absoluta."
fi

if [ "$FORCE" = "1" ] && [ "$CHANNEL" != "api" ]; then
  cv_warn "ATENÇÃO: --force foi usado numa conversa do canal '${CHANNEL:-desconhecido}'."
fi

cv_confirm "Deletar definitivamente a conversa ${CONV_ID} (canal ${CHANNEL:-?})?"

cv_request DELETE "/conversation/${CONV_ID}"

DELETE_OK=$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("1" if isinstance(d, dict) and d.get("success") else "0")
except Exception:
    print("0")
')

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia")
    raise SystemExit
if isinstance(d, dict) and d.get("success"):
    print("Conversa " + str(d.get("conversationId", "")) + " deletada (canal " + str(d.get("channel", "?")) + ").")
    if d.get("message"):
        print(d["message"])
else:
    msg = ""
    if isinstance(d, dict):
        msg = d.get("message") or d.get("error") or ""
    print(f"Falha ao deletar: {msg or raw.strip()}")
    raise SystemExit(1)
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"

[ "$DELETE_OK" = "1" ] || exit 1
