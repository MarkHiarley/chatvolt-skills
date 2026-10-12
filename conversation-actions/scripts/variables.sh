#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — variables (variáveis de CONVERSA)
#
# Lista, lê, define (upsert) e apaga as variáveis de contexto de uma conversa.
# O agente pode consultar esses valores durante o atendimento.
#
# Uso:
#   variables.sh [api-key] <conversation-id> list
#   variables.sh [api-key] <conversation-id> get    --name <varName>
#   variables.sh [api-key] <conversation-id> set    --name <varName> --value "<valor>"
#   variables.sh [api-key] <conversation-id> delete --name <varName> [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
variables.sh — variáveis de conversa do Chatvolt (list/get/set/delete)

Uso:
  variables.sh [api-key] <conversation-id> list
  variables.sh [api-key] <conversation-id> get    --name <varName>
  variables.sh [api-key] <conversation-id> set    --name <varName> --value "<valor>"
  variables.sh [api-key] <conversation-id> delete --name <varName> [--yes]

Argumentos:
  <conversation-id>  id da conversa

Subcomandos:
  list    GET    /variables/{conversationId}                (array na raiz)
  get     GET    /variables/{conversationId}/{varName}       (objeto na raiz)
  set     POST   /variables  {conversationId,varName,varValue} (cria OU atualiza)
  delete  DELETE /variables/{conversationId}/{varName}

Opções:
  --name <varName>   nome da variável (máx. 20 caracteres)
  --value "<valor>"  valor da variável (máx. 100 caracteres)
  --yes              não pede confirmação (delete)
  -h, --help         mostra esta ajuda

Limites do contrato: conversationId até 50, varName até 20, varValue até 100
caracteres (validados aqui antes de chamar a API).

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
ACTION=""
NAME=""
VALUE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)    [ -n "${2:-}" ] || cv_die "--name exige o nome da variável"; NAME="$2"; shift 2 ;;
    --value)   [ -n "${2:-}" ] || cv_die "--value exige o valor da variável"; VALUE="$2"; shift 2 ;;
    --yes)     CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift
               elif [ -z "$ACTION" ]; then ACTION="$1"; shift
               else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }
[ -n "$ACTION" ] || { usage >&2; cv_die "informe o subcomando: list, get, set ou delete"; }

case "$ACTION" in
  list) ;;
  get)    [ -n "$NAME" ] || cv_die "o subcomando get exige --name <varName>" ;;
  set)    [ -n "$NAME" ] || cv_die "o subcomando set exige --name <varName>"
          [ -n "$VALUE" ] || cv_die "o subcomando set exige --value \"<valor>\"" ;;
  delete) [ -n "$NAME" ] || cv_die "o subcomando delete exige --name <varName>" ;;
  *) cv_die "subcomando inválido: '$ACTION' — use list, get, set ou delete" ;;
esac

[ -n "$NAME" ] && [ "${#NAME}" -gt 20 ] && cv_die "--name tem ${#NAME} caracteres; a API aceita no máximo 20"
[ -n "$VALUE" ] && [ "${#VALUE}" -gt 100 ] && cv_die "--value tem ${#VALUE} caracteres; a API aceita no máximo 100"

API_KEY=$(cv_req_key "$API_KEY_ARG")

print_vars() {
  cv_emit "$1" 'import json,sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else [d]
if not items:
    print("(nenhuma variável)")
for v in items:
    if not isinstance(v, dict):
        print(v); continue
    print("%s = %s" % (v.get("varName", "?"), v.get("varValue", "")))
'
}

case "$ACTION" in
  list)
    cv_get "/variables/${CONV_ID}"
    print_vars "$CV_RESP"
    ;;
  get)
    cv_get "/variables/${CONV_ID}/${NAME}"
    print_vars "$CV_RESP"
    ;;
  set)
    BODY=$(python3 - "$CONV_ID" "$NAME" "$VALUE" <<'PY'
import json, sys
print(json.dumps({"conversationId": sys.argv[1], "varName": sys.argv[2], "varValue": sys.argv[3]}, ensure_ascii=False))
PY
)
    cv_request POST "/variables" "$BODY"
    print_vars "$CV_RESP"
    ;;
  delete)
    cv_confirm "Apagar a variável '${NAME}' da conversa ${CONV_ID}?"
    cv_request DELETE "/variables/${CONV_ID}/${NAME}"
    if [ -z "$CV_RESP" ] || [ "$CV_RESP" = "null" ]; then
      cv_info "variável ${NAME} apagada"
    else
      cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
print("OK:", d.get("message") or d.get("success")) if isinstance(d, dict) else print(d)'
    fi
    ;;
esac
