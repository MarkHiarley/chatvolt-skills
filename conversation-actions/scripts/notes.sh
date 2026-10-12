#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — notes
#
# CRUD das notas internas de uma conversa (notas NÃO são enviadas ao cliente).
# Um único script com subcomando via --action.
#
# Uso:
#   notes.sh [api-key] <conversation-id> --action list
#   notes.sh [api-key] <conversation-id> --action create --note "<texto>" [--private|--public] [--justify]
#   notes.sh [api-key] <conversation-id> --action update --note-id <id> [--note "<texto>"] [--private|--public]
#   notes.sh [api-key] <conversation-id> --action delete --note-id <id> [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
notes.sh — notas internas de uma conversa do Chatvolt (list/create/update/delete)

Uso:
  notes.sh [api-key] <conversation-id> --action list
  notes.sh [api-key] <conversation-id> --action create --note "<texto>" [--private|--public] [--justify]
  notes.sh [api-key] <conversation-id> --action update --note-id <id> [--note "<texto>"] [--private|--public]
  notes.sh [api-key] <conversation-id> --action delete --note-id <id> [--yes]

Argumentos:
  <conversation-id>        id da conversa

Opções:
  --action <sub>           list | create | update | delete (obrigatório)
  --note "<texto>"         texto da nota (create exige; update opcional; máx. 500 caracteres)
  --note-id <id>           id da nota (obrigatório em update/delete)
  --private                nota privada (visível só para quem a criou)
  --public                 nota visível para a equipe (padrão da API)
  --justify                marca a nota como justificativa (create; só admin)
  --notification-datetime <ISO>
                           agenda a notificação da nota (ISO 8601, ex. 2026-10-20T09:00:00Z)
  --yes                    não pede confirmação (update/delete)
  -h, --help               mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY         API key (alternativa ao 1º argumento)
  CV_JSON=1                imprime somente JSON em stdout
  CV_YES=1                 pula a confirmação interativa
  CV_API_BASE              base URL alternativa (default https://api.chatvolt.ai)

Notas:
  GET    /conversations/{id}/notes              lista SÓ as notas não privadas
  POST   /conversations/{id}/notes              cria (resposta 201)
  PUT    /conversations/{id}/notes/{noteId}     atualiza
  DELETE /conversations/{id}/notes/{noteId}     remove (resposta 204, corpo vazio)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
ACTION=""
NOTE=""
NOTE_ID=""
PRIVATE=""
JUSTIFY=false
NOTIF=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --action)                [ -n "${2:-}" ] || cv_die "--action exige o subcomando"; ACTION="$2"; shift 2 ;;
    --note)                  [ -n "${2:-}" ] || cv_die "--note exige o texto da nota"; NOTE="$2"; shift 2 ;;
    --note-id)               [ -n "${2:-}" ] || cv_die "--note-id exige o id da nota"; NOTE_ID="$2"; shift 2 ;;
    --private)               PRIVATE=true; shift ;;
    --public)                PRIVATE=false; shift ;;
    --justify)               JUSTIFY=true; shift ;;
    --notification-datetime) [ -n "${2:-}" ] || cv_die "--notification-datetime exige uma data ISO 8601"; NOTIF="$2"; shift 2 ;;
    --yes)                   CV_YES=1; shift ;;
    -h|--help)               usage; exit 0 ;;
    -*)                      cv_die "opção desconhecida: $1 (use --help)" ;;
    *)                       if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }
[ -n "$ACTION" ] || { usage >&2; cv_die "informe --action list|create|update|delete"; }

case "$ACTION" in
  list|create|update|delete) ;;
  *) cv_die "subcomando inválido: '$ACTION' — use list, create, update ou delete" ;;
esac

[ -n "$NOTE" ] && [ "${#NOTE}" -gt 500 ] && cv_die "--note tem ${#NOTE} caracteres; a API aceita no máximo 500"

case "$ACTION" in
  create) [ -n "$NOTE" ] || cv_die "--action create exige --note \"<texto>\"" ;;
  update) [ -n "$NOTE_ID" ] || cv_die "--action update exige --note-id <id>" ;;
  delete) [ -n "$NOTE_ID" ] || cv_die "--action delete exige --note-id <id>" ;;
esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

print_notes() {
  cv_emit "$1" 'import json,sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else [d]
if not items:
    print("(nenhuma nota)")
for n in items:
    if not isinstance(n, dict):
        print(n); continue
    priv = "privada" if n.get("isPrivate") else "publica"
    print("%s | %s | %s | %s" % (
        n.get("id", "?"), priv,
        (n.get("createdAt") or "")[:19].replace("T", " "),
        (n.get("note") or "").replace("\n", " ")))
'
}

case "$ACTION" in
  list)
    cv_get "/conversations/${CONV_ID}/notes"
    print_notes "$CV_RESP"
    ;;
  create)
    BODY=$(python3 - "$NOTE" "$PRIVATE" "$JUSTIFY" "$NOTIF" <<'PY'
import json, sys
note, private, justify, notif = sys.argv[1:5]
b = {"note": note, "isJustify": justify == "true"}
if private:
    b["isPrivate"] = private == "true"
if notif:
    b["notificationDateTime"] = notif
print(json.dumps(b, ensure_ascii=False))
PY
)
    cv_request POST "/conversations/${CONV_ID}/notes" "$BODY"
    print_notes "$CV_RESP"
    ;;
  update)
    BODY=$(python3 - "$NOTE" "$PRIVATE" "$NOTIF" <<'PY'
import json, sys
note, private, notif = sys.argv[1:4]
b = {}
if note:
    b["note"] = note
if private:
    b["isPrivate"] = private == "true"
if notif:
    b["notificationDateTime"] = notif
print(json.dumps(b, ensure_ascii=False))
PY
)
    cv_confirm "Atualizar a nota ${NOTE_ID} da conversa ${CONV_ID}?"
    cv_request PUT "/conversations/${CONV_ID}/notes/${NOTE_ID}" "$BODY"
    print_notes "$CV_RESP"
    ;;
  delete)
    cv_confirm "Apagar a nota ${NOTE_ID} da conversa ${CONV_ID}?"
    cv_request DELETE "/conversations/${CONV_ID}/notes/${NOTE_ID}"
    if [ -z "$CV_RESP" ] || [ "$CV_RESP" = "null" ]; then
      cv_info "nota ${NOTE_ID} apagada"
    else
      cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
print("OK:", d.get("message") or d.get("success")) if isinstance(d, dict) else print(d)'
    fi
    ;;
esac
