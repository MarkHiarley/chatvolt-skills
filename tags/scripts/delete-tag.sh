#!/usr/bin/env bash
# delete-tag.sh — remove uma tag da organização pelo nome (POST /tags/delete-by-name).
#
# Operação destrutiva: exige confirmação (CV_YES=1 ou --yes para automações).
# ATENÇÃO: nesta organização/plano a rota responde 404 (a doc pública lista, a
# API não expõe aqui). O script detecta esse 404 e explica o caso.
# Contrato e disponibilidade: SOURCES.md §6.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: delete-tag.sh [<api-key>] <nome> [--yes]

Remove uma tag da organização pelo nome. A rota é POST /tags/delete-by-name
(o openapi.yaml define POST; a página narrativa da doc mostra DELETE).

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)
  <nome>             Nome exato da tag a remover (como em list-tags.sh)

Opções:
  --yes              Não pede confirmação (equivale a CV_YES=1)
  -h, --help         Mostra esta ajuda

Saída (CV_JSON=1):
  {"name","success","response"} — "success" reflete o HTTP 2xx; "response" é o
  corpo da API desembrulhado.

Disponibilidade (medida ao vivo em 2026-10-12):
  POST /tags/delete-by-name responde 404 nesta organização: a API devolve a
  página HTML de 404 do dashboard, não o JSON da API. O script explica o caso e
  sai 1 — nenhuma tag é removida. Veja SOURCES.md §6.

Exemplos:
  delete-tag.sh "$CHATVOLT_API_KEY" urgente
  CV_YES=1 delete-tag.sh "$CHATVOLT_API_KEY" urgente

Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

# cv_tags_req <METHOD> <path> [<json-body>] [args extras do curl...]
# As três rotas de tags respondem 404 neste ambiente: cv_request morreria no
# 404 e perderíamos o código HTTP e o corpo. Aqui ele roda num subshell, que
# grava CV_STATUS/CV_RESP em arquivos temporários antes de sair; no 404 o
# script explica o caso (não é bug nem key errada) e sai 1. Os demais erros
# (401/402/5xx/rede) mantêm o tratamento padrão do helper.
cv_tags_req() {
  local method="$1" path="$2" body="${3-}"
  shift 2
  if [ "$#" -gt 0 ]; then shift 1; fi
  local tmp out rc
  tmp="$(mktemp -d)" || cv_die "não foi possível criar diretório temporário"
  set +e
  out="$(
    trap 'printf "%s" "$CV_STATUS" >"$tmp/status"; printf "%s" "$CV_RESP" >"$tmp/body"' EXIT
    cv_request "$method" "$path" "$body" "$@" 2>&1
  )"
  rc=$?
  set -e
  CV_STATUS="$(cat "$tmp/status" 2>/dev/null || true)"
  CV_RESP="$(cat "$tmp/body" 2>/dev/null || true)"
  rm -rf "$tmp"
  if [ "$rc" = "0" ]; then
    # A doc de /tags devolve {data, success, error:null} no sucesso, e o
    # cv_unwrap só desembrulha quando a chave "error" está AUSENTE: segunda
    # passada para os scripts receberem sempre o payload (array ou objeto).
    CV_RESP="$(printf '%s' "$(cv_unwrap "$CV_RESP")" | python3 -c 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and not d.get("error"):
    d = d["data"]
print(json.dumps(d, ensure_ascii=False))')"
    return 0
  fi
  if [ "$CV_STATUS" = "404" ]; then cv_tags_404 "$method" "$path"; fi
  printf '%s\n' "$out" >&2
  exit "$rc"
}

# cv_tags_404 <METHOD> <path> — explica a rota de tags ausente neste ambiente.
cv_tags_404() {
  local resumo
  case "$CV_RESP" in
    '<!DOCTYPE'*|'<html'*|'<!doctype'*) resumo="página HTML de 404 do dashboard (não é JSON da API)" ;;
    *) resumo="corpo: $(cv_err_msg "$CV_RESP")" ;;
  esac
  {
    printf 'ERRO: %s %s respondeu 404 — esta rota de tags não é exposta neste plano/organização.\n' "$1" "$2"
    printf '  Resposta: %s\n' "$resumo"
    printf '  A documentação lista a rota (https://chat-volt.mintlify.app/pages/tags/reference),\n'
    printf '  mas a API devolve 404 aqui: não é falha do script nem da chave de API.\n'
    printf '  Medido ao vivo em 2026-10-12: /tags, /tags/delete-by-name e /tags/get-visible-tags\n'
    printf '  respondem 404 nesta organização (SOURCES.md §6).\n'
    printf '  Nenhuma tag foi removida. Alternativas: revalidar depois com a skill chatvolt-api-call\n'
    printf '  (call.sh <key> POST /tags/delete-by-name) ou remover a tag pelo dashboard do Chatvolt.\n'
  } >&2
  exit 1
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift

NAME="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) export CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done
[ -n "$NAME" ] || { usage >&2; cv_die "informe o <nome> da tag a remover"; }

cv_confirm "Remover a tag \"$NAME\" da organização (POST /tags/delete-by-name)?"

PAYLOAD="$(python3 - "$NAME" <<'PY'
import json, sys
print(json.dumps({"name": sys.argv[1]}, ensure_ascii=False))
PY
)"

cv_tags_req POST /tags/delete-by-name "$PAYLOAD"
RESP="$CV_RESP"

if [ "$CV_JSON" = "1" ]; then
  python3 - "$NAME" "$RESP" <<'PY'
import json, sys
try:
    resp = json.loads(sys.argv[2])
except ValueError:
    resp = sys.argv[2]
print(json.dumps({"name": sys.argv[1], "success": True, "response": resp}, ensure_ascii=False))
PY
else
  printf 'Tag "%s" removida (HTTP %s).\n' "$NAME" "$CV_STATUS"
  if [ -n "$RESP" ] && [ "$RESP" != "{}" ] && [ "$RESP" != "null" ]; then
    printf '%s' "$RESP" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("Resposta da API: " + json.dumps(d, ensure_ascii=False))'
  fi
fi
