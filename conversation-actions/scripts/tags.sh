#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — tags (tags de CONVERSA)
#
# Lista e adiciona etiquetas em uma conversa.
#
# ATENÇÃO: GET/POST /conversations/{id}/tags NÃO aceitam API key neste
# ambiente — respondem 401 com um Bearer válido (o endpoint usa a sessão do
# dashboard, via cookie). Este script detecta o 401 e explica, em vez de
# sugerir que a chave está errada.
#
# Uso:
#   tags.sh [api-key] <conversation-id> list
#   tags.sh [api-key] <conversation-id> add --tag <nome> [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula a confirmação interativa
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
tags.sh — etiquetas de uma conversa do Chatvolt (list/add)

Uso:
  tags.sh [api-key] <conversation-id> list
  tags.sh [api-key] <conversation-id> add --tag <nome> [--yes]

Argumentos:
  <conversation-id>  id da conversa
  <list|add>         list  = GET  /conversations/{id}/tags
                     add   = POST /conversations/{id}/tags {"tagName": "<nome>"}

Opções:
  --tag <nome>       nome da etiqueta (obrigatório em add)
  --yes              não pede confirmação (add)
  -h, --help         mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY   API key (alternativa ao 1º argumento)
  CV_JSON=1          imprime somente JSON em stdout
  CV_YES=1           pula a confirmação interativa
  CV_API_BASE        base URL alternativa (default https://api.chatvolt.ai)

Disponibilidade (medida ao vivo em 2026-10-12):
  GET  /conversations/{id}/tags → 401 "Usuário não autenticado ou organização
                                     não encontrada." mesmo com API key válida
  POST /conversations/{id}/tags → 401 idem
  Estes dois endpoints exigem a sessão do dashboard (cookie), não API key.
  As etiquetas de conversa continuam visíveis no dashboard e podem ser filtradas
  em GET /conversation?tag=<nome>. Para etiquetas de BASE (datastore), use a
  skill chatvolt-datastore-tags.

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
ACTION=""
TAG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)     [ -n "${2:-}" ] || cv_die "--tag exige o nome da etiqueta"; TAG="$2"; shift 2 ;;
    --yes)     CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift
               elif [ -z "$ACTION" ]; then ACTION="$1"; shift
               else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }
[ -n "$ACTION" ] || { usage >&2; cv_die "informe o subcomando: list ou add"; }

case "$ACTION" in
  list) ;;
  add) [ -n "$TAG" ] || cv_die "--tag <nome> é obrigatório no subcomando add" ;;
  *) cv_die "subcomando inválido: '$ACTION' — use list ou add" ;;
esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

# Faz a chamada capturando o erro do helper: o 401 das etiquetas é o esperado
# aqui e precisa de uma explicação própria (não é problema da API key).
call_tags() {
  local method="$1" body="${2:-}" tmp err rc msg
  tmp=$(mktemp); err=$(mktemp)
  set +e
  ( cv_request "$method" "/conversations/${CONV_ID}/tags" "$body"; printf '%s' "$CV_RESP" > "$tmp" ) 2>"$err"
  rc=$?
  set -e
  msg=$(cat "$err")
  rm -f "$err"
  if [ "$rc" != 0 ]; then
    rm -f "$tmp"
    if printf '%s' "$msg" | grep -q '401'; then
      cv_die "a API respondeu 401 em ${method} /conversations/${CONV_ID}/tags mesmo com a API key válida: este endpoint não aceita API key — ele exige a sessão do dashboard (cookie). Não é problema da sua chave; use o dashboard para ver/editar etiquetas de conversa ou filtre por etiqueta com 'GET /conversation?tag=<nome>' (skill chatvolt-conversation-cleanup)."
    fi
    printf '%s\n' "$msg" >&2
    exit "$rc"
  fi
  CAT_RESP=$(cat "$tmp"); rm -f "$tmp"
}

if [ "$ACTION" = "add" ]; then
  BODY=$(python3 - "$TAG" <<'PY'
import json, sys
print(json.dumps({"tagName": sys.argv[1]}, ensure_ascii=False))
PY
)
  cv_confirm "Adicionar a etiqueta '${TAG}' à conversa ${CONV_ID}?"
  call_tags POST "$BODY"
else
  call_tags GET ""
fi

cv_emit "$CAT_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, list):
    if not d:
        print("(nenhuma etiqueta)")
    for t in d:
        print(t.get("name") or t.get("tagName") or t if isinstance(t, dict) else t)
elif isinstance(d, dict):
    print("OK:", d.get("message") or d.get("success"))
else:
    print(d)'
