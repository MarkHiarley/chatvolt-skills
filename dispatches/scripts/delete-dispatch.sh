#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Deletar um disparo (campanha em massa).
#
# Particularidades reais da rota (medidas em 2026-10-12):
#   * NÃO existe GET /dispatches/{id}: o path responde 404 (página do dashboard).
#     Para conferir o disparo antes de apagar, a listagem GET /dispatches é varrida.
#   * DELETE /dispatches?id=<inexistente> responde HTTP 500 com
#     {"error":"Dispatch not found or you do not have permission to delete it."}
#     (o openapi documenta 404) — por isso o script confere a existência antes.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./delete-dispatch.sh <api-key> <dispatch-id> [--force]

Deleta um disparo (a campanha e seus dados associados).
  DELETE /dispatches?id=<dispatch-id>

Antes de apagar, o script varre GET /dispatches (100 por página) para mostrar
nome/status do disparo — porque GET /dispatches/{id} NÃO existe (responde 404).
Depois pede confirmação humana (pule com CV_YES=1 em automação).

Opções:
  --force      não confere a existência antes (apaga direto após a confirmação);
               use quando a listagem não devolver o disparo
  -h, --help   mostra esta ajuda

Exemplos:
  ./delete-dispatch.sh "$CHATVOLT_API_KEY" cmrxn7snz01wlvgqwubuhidi2
  CV_YES=1 ./delete-dispatch.sh "$CHATVOLT_API_KEY" "$DISPATCH_ID"

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

FORCE=0
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DISPATCH_ID="${POS[1]:-}"
[ -n "$DISPATCH_ID" ] || cv_die "informe o id do disparo: delete-dispatch.sh <api-key> <dispatch-id>"

FOUND=""
if [ "$FORCE" != "1" ]; then
  TMPD=$(mktemp -d)
  trap 'rm -rf "$TMPD"' EXIT
  OFF=0
  PAGE=0
  while :; do
    cv_get "/dispatches?offset=${OFF}&limit=100"
    printf '%s' "$CV_RESP" > "${TMPD}/${PAGE}.json"
    RES=$(python3 - "${TMPD}/${PAGE}.json" "$DISPATCH_ID" <<'PY'
import json, sys

d = json.load(open(sys.argv[1], encoding="utf-8"))
items = d.get("dispatches") if isinstance(d, dict) else (d if isinstance(d, list) else [])
items = items or []
hit = next((x for x in items if str(x.get("id")) == sys.argv[2]), None)
print(json.dumps({"n": len(items), "found": hit}, ensure_ascii=False))
PY
)
    FOUND=$(python3 -c 'import json,sys; v=json.loads(sys.argv[1])["found"]; print(json.dumps(v, ensure_ascii=False) if v else "")' "$RES")
    N=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["n"])' "$RES")
    [ -n "$FOUND" ] && break
    [ "$N" -ge 100 ] || break
    PAGE=$((PAGE + 1))
    OFF=$((OFF + N))
  done
  if [ -z "$FOUND" ]; then
    cv_die "disparo '${DISPATCH_ID}' não encontrado em GET /dispatches (a API não expõe GET /dispatches/{id}; a listagem foi varrida por completo). Confira o id ou use --force para apagar mesmo assim"
  fi
  if [ "$CV_JSON" != "1" ]; then
    printf '%s' "$FOUND" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("Disparo a deletar:")
for label, key in (("id", "id"), ("nome", "name"), ("status", "status"), ("agente", "agentId")):
    print("  " + (label + ":").ljust(8) + " " + str(d.get(key)))
'
  fi
fi

cv_confirm "Deletar o disparo ${DISPATCH_ID}? A campanha e seus dados associados serão removidos"
cv_warn "DELETE /dispatches?id=${DISPATCH_ID} — operação irreversível."

Q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.urlencode({"id": sys.argv[1]}))' "$DISPATCH_ID")
cv_request DELETE "/dispatches?${Q}"

if [ "$CV_JSON" = "1" ]; then
  if [ -z "$CV_RESP" ]; then printf '%s\n' '{"success":true}'; else cv_emit "$CV_RESP"; fi
else
  echo "Disparo ${DISPATCH_ID} deletado."
fi
