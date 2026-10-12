#!/usr/bin/env bash
# add-tag.sh — acrescenta etiquetas a uma fonte (wrapper de set-tags.sh).
#
# A API não tem endpoint de "adicionar etiqueta": o upsert grava a lista final
# em config.tags, então o wrapper lê as etiquetas atuais, faz a união e delega
# para set-tags.sh (padrão: isUpdateText=false, sem reenviar texto).
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: add-tag.sh <api-key> <datastore-id> <source-id> <etiqueta>[,<etiqueta>…]
     [--text-file <arquivo> | --text "<conteúdo>"] [--yes]

Acrescenta uma ou mais etiquetas às etiquetas atuais da fonte, preservando as
existentes, e grava via upsert POST /datasources (não existe PATCH de fonte).

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)
  <datastore-id>     ID da base (sufixo _v3)
  <source-id>        ID da fonte
  <etiqueta…>        etiquetas separadas por vírgula (sem espaços internos)

Modo de texto (opcional — o padrão preserva o conteúdo):
  --reuse-text       não reenvia o texto: só as etiquetas mudam e o conteúdo
                     indexado é preservado (recomendado)
  --text-file <f>    reenvia o texto do arquivo; em fonte existente a API aceita
                     mas NÃO substitui o conteúdo indexado (sai 1 avisando)
  --text "<c>"       idem, com o conteúdo literal

Opções: --yes (não pede confirmação) · -h, --help

Exemplos:
  add-tag.sh "$CHATVOLT_API_KEY" <base> <fonte> financeiro --reuse-text
  add-tag.sh "$CHATVOLT_API_KEY" <base> <fonte> a,b --reuse-text --yes

Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift
DS="${1:-}"; shift || true
SRC="${1:-}"; shift || true
[ -n "$DS" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$SRC" ] || { usage >&2; cv_die "informe o <source-id>"; }
NEW="${1:-}"; shift || true
[ -n "$NEW" ] || { usage >&2; cv_die "informe a(s) etiqueta(s) a acrescentar"; }

PASS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --text-file) [ -n "${2:-}" ] || cv_die "--text-file exige o caminho do arquivo"; PASS+=(--text-file "$2"); shift 2 ;;
    --text)      [ -n "${2:-}" ] || cv_die "--text exige o conteúdo"; PASS+=(--text "$2"); shift 2 ;;
    --reuse-text|--yes) PASS+=("$1"); shift ;;
    -h|--help)   usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

cv_get "/datasources/${SRC}?idstore=${DS}"

FINAL=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys
d = json.load(sys.stdin)
if d.get("datastoreId") != sys.argv[2]:
    sys.stderr.write("ERRO: a fonte %s pertence à base %s, não a %s — confira os IDs\n"
                     % (d.get("id"), d.get("datastoreId"), sys.argv[2]))
    raise SystemExit(1)
cur = [str(t) for t in ((d.get("config") or {}).get("tags") or [])]
new = [p.strip() for p in sys.argv[1].split(",") if p.strip()]
out = list(cur)
for t in new:
    if t not in out:
        out.append(t)
sys.stderr.write("AVISO: etiquetas %s → %s\n" % (cur if cur else "(nenhuma)", out))
print(",".join(out))' "$NEW" "$DS")

exec "$(dirname "$0")/set-tags.sh" "$API_KEY" "$DS" "$SRC" --tags "$FINAL" ${PASS[@]+"${PASS[@]}"}
