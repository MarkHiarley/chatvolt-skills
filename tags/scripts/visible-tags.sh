#!/usr/bin/env bash
# visible-tags.sh — lista as tags visíveis da organização (GET /tags/get-visible-tags).
#
# As tags visíveis são as que o dashboard exibe para uso nas conversas e
# contatos. ATENÇÃO: nesta organização/plano a rota responde 404 (a doc pública
# lista, a API não expõe aqui). O script detecta esse 404 e explica o caso.
# Contrato e disponibilidade: SOURCES.md §6.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: visible-tags.sh [<api-key>]

Lista as tags visíveis da organização (GET /tags/get-visible-tags), ou seja, as
que o dashboard mostra para aplicar em conversas e contatos.

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)

Opções:
  -h, --help         Mostra esta ajuda

Saída (CV_JSON=1):
  [{"id","name","color"}] — o envelope {data, success, error:null} da doc é desembrulhado.

Diferença para list-tags.sh:
  list-tags.sh usa GET /tags (todas as tags da organização); este usa
  GET /tags/get-visible-tags (apenas as visíveis no dashboard).

Disponibilidade (medida ao vivo em 2026-10-12):
  GET /tags/get-visible-tags responde 404 nesta organização: a API devolve a
  página HTML de 404 do dashboard, não o JSON da API. O script explica o caso e
  sai 1 — não é falha da chave. Veja SOURCES.md §6.

Exemplos:
  visible-tags.sh "$CHATVOLT_API_KEY"
  CV_JSON=1 visible-tags.sh "$CHATVOLT_API_KEY"

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
    printf '  Alternativas: revalidar depois com a skill chatvolt-api-call\n'
    printf '  (call.sh <key> GET /tags/get-visible-tags) ou ver as tags no dashboard do Chatvolt.\n'
  } >&2
  exit 1
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift
[ $# -eq 0 ] || cv_die "argumento inesperado: $1 (use -h para a ajuda)"

cv_tags_req GET /tags/get-visible-tags ""

LIST="$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    d = d.get("data") or d.get("tags") or []
if not isinstance(d, list):
    d = []
out = []
for t in d:
    if isinstance(t, dict):
        out.append({"id": t.get("id"), "name": t.get("name"), "color": t.get("color")})
print(json.dumps(out, ensure_ascii=False))')"

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$LIST"
else
  printf '%s' "$LIST" | python3 -c 'import json,sys
tags = json.load(sys.stdin)
print("Tags visíveis da organização: %d" % len(tags))
if not tags:
    print("")
    print("Nenhuma tag visível retornada pela API.")
else:
    print("")
    print("ID".ljust(26) + "NOME".ljust(24) + "COR")
    for t in tags:
        print(str(t.get("id") or "").ljust(26) + str(t.get("name") or "").ljust(24) + str(t.get("color") or ""))
'
fi
