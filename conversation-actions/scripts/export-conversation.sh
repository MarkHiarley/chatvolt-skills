#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — export-conversation
#
# Baixa a exportação de UMA conversa. A resposta é BINÁRIA (planilha xlsx),
# então o script salva em arquivo (--out) — é o único caso desta skill que usa
# curl direto, porque o helper da lib só lida com JSON em memória.
#
# Uso:
#   export-conversation.sh [api-key] <conversation-id> [--out <arquivo>]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
export-conversation.sh — baixa a exportação (binária) de uma conversa do Chatvolt

Uso:
  export-conversation.sh [api-key] <conversation-id> [--out <arquivo>]

Argumentos:
  <conversation-id>  id da conversa a exportar

Opções:
  --out <arquivo>    caminho do arquivo de saída. Sem --out o nome é derivado:
                     "./<conversation-id>.<ext>" (a extensão vem do Content-Type
                     da resposta: .xlsx, .csv, .json, .zip ou .txt)
  -h, --help         mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY   API key (alternativa ao 1º argumento)
  CV_JSON=1          imprime somente JSON em stdout ({"out","bytes","contentType"})
  CV_API_BASE        base URL alternativa (default https://api.chatvolt.ai)

Endpoint: GET /conversations/{conversationId}/export
Medido ao vivo (2026-10-12): 200 com Content-Type
application/vnd.openxmlformats-officedocument.spreadsheetml.sheet (planilha xlsx).
Não existe exportação em lote utilizável: GET /conversations/export responde 404
neste ambiente.

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --out)     [ -n "${2:-}" ] || cv_die "--out exige o caminho do arquivo"; OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }

API_KEY=$(cv_req_key "$API_KEY_ARG")

TMP=$(mktemp); HDR=$(mktemp)
cleanup() { rm -f "$TMP" "$HDR"; }
trap cleanup EXIT

CODE=$(curl -sS --max-time "${CV_TIMEOUT:-120}" -D "$HDR" -o "$TMP" -w '%{http_code}' \
         -H "Authorization: Bearer ${API_KEY}" \
         "${CV_BASE_URL}/conversations/${CONV_ID}/export") \
  || cv_die "falha de rede ao baixar a exportação da conversa ${CONV_ID}" 4

if [ "${CODE:0:1}" != "2" ]; then
  BODY=$(cat "$TMP" 2>/dev/null || true)
  case "$CODE" in
    402) cv_die "HTTP 402 (quota): $(cv_err_msg "$BODY")" 3 ;;
    401|403) cv_die "HTTP ${CODE} (não autorizado): $(cv_err_msg "$BODY") — confira a API key e as permissões da organização" ;;
    404) cv_die "HTTP 404 (não encontrado): conversa ${CONV_ID} não existe ou não pertence à organização — $(cv_err_msg "$BODY")" ;;
    5*)  cv_die "HTTP ${CODE} (erro interno do servidor): $(cv_err_msg "$BODY")" 5 ;;
    *)   cv_die "HTTP ${CODE}: $(cv_err_msg "$BODY")" ;;
  esac
fi

CTYPE=$(grep -i '^content-type:' "$HDR" | tail -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//')
case "$CTYPE" in
  *spreadsheetml*) EXT="xlsx" ;;
  *csv*)           EXT="csv" ;;
  *json*)          EXT="json" ;;
  *zip*)           EXT="zip" ;;
  *text/plain*)    EXT="txt" ;;
  *)               EXT="bin" ;;
esac

[ -n "$OUT" ] || OUT="./${CONV_ID}.${EXT}"

mv -f "$TMP" "$OUT"
rm -f "$HDR"
trap - EXIT

BYTES=$(wc -c < "$OUT" | tr -d ' ')

if [ "$CV_JSON" = "1" ]; then
  python3 - "$OUT" "$BYTES" "$CTYPE" <<'PY'
import json, sys
print(json.dumps({"out": sys.argv[1], "bytes": int(sys.argv[2]), "contentType": sys.argv[3]}, ensure_ascii=False))
PY
else
  cv_info "arquivo: ${OUT} (${BYTES} bytes, ${CTYPE:-content-type desconhecido})"
fi
