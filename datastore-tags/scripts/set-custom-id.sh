#!/usr/bin/env bash
# set-custom-id.sh — define/remove o config.custom_id de uma fonte (wrapper de set-tags.sh).
#
# custom_id é o filtro real de recuperação (filters.custom_ids no POST /datastores/{id}/query);
# a etiqueta (config.tags) é só metadado local. Como não existe PATCH de fonte,
# a gravação é um upsert POST /datasources.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: set-custom-id.sh <api-key> <datastore-id> <source-id> (<custom-id> | --clear)
     [--text-file <arquivo> | --text "<conteúdo>"] [--yes]

Define (ou remove, com --clear) o config.custom_id de UMA fonte. O custom_id é
o valor que a busca filtra via filters.custom_ids — use um id por tenant/cliente
para multi-tenant.

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)
  <datastore-id>     ID da base (sufixo _v3)
  <source-id>        ID da fonte
  <custom-id>        valor do filtro (ex.: tenant-x)
  --clear            remove o custom_id em vez de definir

Modos de texto (um é obrigatório — regra do set-tags.sh):
  --reuse-text       não reenvia o texto: só o custom_id muda e o conteúdo
                     indexado é preservado (recomendado)
  --text-file <f>    reenvia o texto do arquivo; em fonte existente a API aceita
                     mas NÃO substitui o conteúdo indexado (sai 1 avisando)
  --text "<c>"       idem, com o conteúdo literal

Opções: --yes (não pede confirmação) · -h, --help

Exemplos:
  set-custom-id.sh "$CHATVOLT_API_KEY" <base> <fonte> tenant-x
  set-custom-id.sh "$CHATVOLT_API_KEY" <base> <fonte> --clear
  query-verify.sh "$CHATVOLT_API_KEY" <base> "pergunta do tenant" --custom-id tenant-x

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
[ $# -ge 1 ] || { usage >&2; cv_die "informe o <custom-id> (ou --clear)"; }

CUSTOM=""
case "$1" in
  --clear) CUSTOM=""; shift ;;
  -*) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  *) CUSTOM="$1"; shift ;;
esac
case "$CUSTOM" in *","*) cv_die "o custom_id não deve conter vírgula (a API usa um id por fonte)" ;; esac

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

if [ -n "$CUSTOM" ]; then
  exec "$(dirname "$0")/set-tags.sh" "$API_KEY" "$DS" "$SRC" --custom-id "$CUSTOM" ${PASS[@]+"${PASS[@]}"}
else
  exec "$(dirname "$0")/set-tags.sh" "$API_KEY" "$DS" "$SRC" --clear-custom-id ${PASS[@]+"${PASS[@]}"}
fi
