#!/usr/bin/env bash
# create-tag.sh — cria uma tag na organização (POST /tags).
#
# ATENÇÃO: nesta organização/plano o POST /tags responde 404 (a doc pública
# lista a rota, a API não a expõe aqui). O script detecta esse 404 e explica o
# caso, em vez de despejar a página HTML devolvida.
# Contrato e disponibilidade: SOURCES.md §6.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: create-tag.sh [<api-key>] --name <nome> [--color <cor>] [--json '<campos-extra>']

Cria uma tag da organização (POST /tags).

Argumentos:
  <api-key>            Chave de API (ou exporte CHATVOLT_API_KEY)

Opções:
  --name <nome>        Nome da tag (obrigatório)
  --color <cor>        Cor da tag como o dashboard a exibe (ex.: red, blue, #ff0000)
  --json '<objeto>'    Campos extras mesclados no corpo da requisição,
                       sobrescrevendo --name/--color
  -h, --help           Mostra esta ajuda

Saída (CV_JSON=1):
  {"id","name","color"} — o envelope {data, success, error:null} da doc é desembrulhado.

Disponibilidade (medida ao vivo em 2026-10-12):
  POST /tags responde 404 nesta organização: a API devolve a página HTML de 404
  do dashboard, não o JSON da API. O script explica o caso e sai 1 — não é
  falha da chave. Veja SOURCES.md §6 e a skill chatvolt-api-call.

Exemplos:
  create-tag.sh "$CHATVOLT_API_KEY" --name urgente --color red
  CV_JSON=1 create-tag.sh "$CHATVOLT_API_KEY" --name vip --json '{"color":"#0af"}'

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
    printf '  Alternativas: revalidar depois com a skill chatvolt-api-call (call.sh <key> POST /tags)\n'
    printf '  ou gerenciar as tags pelo dashboard do Chatvolt.\n'
  } >&2
  exit 1
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift

NAME=""; COLOR=""; EXTRA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --color) COLOR="${2:-}"; shift 2 ;;
    --json) EXTRA="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done
[ -n "$NAME" ] || { usage >&2; cv_die "informe --name <nome-da-tag>"; }

PAYLOAD="$(python3 - "$NAME" "$COLOR" "$EXTRA" <<'PY'
import json, sys
name, color, extra = sys.argv[1], sys.argv[2], sys.argv[3]
body = {"name": name}
if color.strip():
    body["color"] = color.strip()
if extra.strip():
    try:
        ex = json.loads(extra)
    except ValueError as exc:
        sys.stderr.write("ERRO: --json não é JSON válido: %s\n" % exc)
        raise SystemExit(1)
    if not isinstance(ex, dict):
        sys.stderr.write("ERRO: --json precisa ser um objeto JSON (ex.: '{\"color\":\"blue\"}')\n")
        raise SystemExit(1)
    body.update(ex)
print(json.dumps(body, ensure_ascii=False))
PY
)"

cv_tags_req POST /tags "$PAYLOAD"
TAG="$CV_RESP"

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$TAG"
else
  printf '%s' "$TAG" | python3 -c 'import json,sys
t = json.load(sys.stdin)
if not isinstance(t, dict):
    t = {}
print("Tag criada: " + str(t.get("name") or "?"))
if t.get("id"):
    print("ID: " + str(t["id"]))
if t.get("color"):
    print("Cor: " + str(t["color"]))
print("")
print("Confira a listagem com: list-tags.sh <api-key>")
'
fi
