#!/usr/bin/env bash
set -euo pipefail

# chatvolt-mercadolivre — sync-products.sh
# Dispara uma sincronização dos produtos do Mercado Livre
# (POST /mercadolivre/products/sync).
#
# ATENÇÃO: é uma operação de ESCRITA — dispara sincronização real na conta do
# Mercado Livre conectada. Exige --yes explícito (CV_YES=1 sozinho NÃO basta).

usage() {
  cat <<'EOF'
Uso: sync-products.sh <api-key> --yes [--agent <id>] [--service-provider <id>] [--json '<extra>']

Dispara a sincronização dos produtos do Mercado Livre no Chatvolt.

ATENÇÃO: operação de escrita — inicia uma sincronização real. O --yes é
obrigatório e a variável CV_YES=1 NÃO substitui a flag.

Opções:
  --yes                    (obrigatório) confirma a sincronização.
  --agent <id>             id do agente; quando informado vai como query
                           (agentId), no mesmo formato de /mercadolivre/products.
  --service-provider <id>  id do provedor do Mercado Livre (query
                           serviceProviderId).
  --json '<extra>'         objeto JSON opcional enviado como corpo (campos
                           extras aceitos pela rota; ex.: '{"fullSync":true}').
  -h, --help               esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (usado se --agent não for informado)
  CV_JSON=1           imprime SOMENTE JSON em stdout
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Observação: a doc pública não documenta parâmetros nesta rota (o exemplo é um
POST sem corpo). Por isso agentId/serviceProviderId são enviados como query
somente quando informados, e o corpo só existe com --json.

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplos:
  sync-products.sh "$KEY" --agent "$AG" --yes
  sync-products.sh "$KEY" --yes --json '{"fullSync":true}'
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
[ "$#" -ge 1 ] && shift

AGENT_ID=""
SP_ID=""
BODY_JSON=""
YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y)            YES=1; shift ;;
    --agent)             [ -n "${2:-}" ] || cv_die "--agent exige um valor"; AGENT_ID="$2"; shift 2 ;;
    --service-provider)  [ -n "${2:-}" ] || cv_die "--service-provider exige um valor"; SP_ID="$2"; shift 2 ;;
    --json)              [ -n "${2:-}" ] || cv_die "--json exige um valor"; BODY_JSON="$2"; shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

AGENT_ID="${AGENT_ID:-${CHATVOLT_AGENT_ID:-}}"

ml_urlenc() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

[ "$YES" = "1" ] || cv_die "esta operação dispara uma sincronização real do Mercado Livre — confirme com --yes"

ARGS=""
[ -n "$AGENT_ID" ] && ARGS="${ARGS}&agentId=$(ml_urlenc "$AGENT_ID")"
[ -n "$SP_ID" ]    && ARGS="${ARGS}&serviceProviderId=$(ml_urlenc "$SP_ID")"
PATH_SYNC="/mercadolivre/products/sync"
[ -n "$ARGS" ] && PATH_SYNC="${PATH_SYNC}?${ARGS#&}"

PAYLOAD=""
if [ -n "$BODY_JSON" ]; then
  python3 -c 'import json,sys; json.loads(sys.argv[1])' "$BODY_JSON" 2>/dev/null \
    || cv_die "--json precisa ser um JSON válido (recebido: $BODY_JSON)"
  PAYLOAD=$(python3 - "$BODY_JSON" <<'PY'
import json, sys
extra = json.loads(sys.argv[1])
if not isinstance(extra, dict):
    raise SystemExit("o corpo precisa ser um objeto JSON")
print(json.dumps(extra, ensure_ascii=False))
PY
) || cv_die "--json precisa ser um objeto JSON (recebido: $BODY_JSON)"
fi

cv_warn "disparando sincronização real dos produtos do Mercado Livre"
cv_request POST "$PATH_SYNC" "$PAYLOAD"
ROOT=$(cv_unwrap "$CV_RESP")

if [ "$CV_JSON" = "1" ]; then
  [ -n "$ROOT" ] || ROOT='{"success":true}'
  printf '%s\n' "$ROOT"
  exit 0
fi

cv_info "Sincronização dos produtos do Mercado Livre solicitada."
if [ -n "$ROOT" ] && [ "$ROOT" != "null" ]; then
  cv_emit "$ROOT"
fi
