#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Popular a fila de um disparo (inicia os envios reais).
#
# ATENÇÃO: esta rota coloca as mensagens na fila de envio e dispara mensagens
# REAIS para os contatos das listas. O script exige --yes explícito e nunca é
# exercitado ao vivo em teste (a suíte usa apenas o stub offline).
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./populate-queue.sh <api-key> <dispatch-id> --yes

Popula a fila do disparo, considerando as listas de inclusão e exclusão.
  POST /dispatches/<dispatch-id>/populate-queue

⚠️  AVISO: depois de populada, a fila roda em background e as mensagens SÃO
    ENVIADAS de verdade para os contatos (WhatsApp/Telegram/etc. conforme a
    integração da organização). Use --yes para confirmar explicitamente.
    CV_YES=1 NÃO substitui o --yes neste script.

Opções:
  --yes        confirma o disparo real das mensagens
  -h, --help   mostra esta ajuda

Exemplos:
  ./populate-queue.sh "$CHATVOLT_API_KEY" "$DISPATCH_ID" --yes

Como acompanhar: GET /dispatches (list-dispatches.sh) mostra sentCount/totalCount
e a última mensagem de erro do disparo.

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

YES=0
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --yes) YES=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DISPATCH_ID="${POS[1]:-}"
[ -n "$DISPATCH_ID" ] || cv_die "informe o id do disparo: populate-queue.sh <api-key> <dispatch-id> --yes"
[ "$YES" = "1" ] || cv_die "--yes é obrigatório: esta rota popula a fila e ENVIA mensagens reais aos contatos da campanha"

cv_warn "POST /dispatches/${DISPATCH_ID}/populate-queue: a fila será populada e as mensagens REAIS serão enviadas."

REQ_PATH=$(python3 -c 'import sys, urllib.parse; print("/dispatches/" + urllib.parse.quote(sys.argv[1], safe="") + "/populate-queue")' "$DISPATCH_ID")
cv_request POST "$REQ_PATH"

if [ "$CV_JSON" = "1" ]; then
  if [ -z "$CV_RESP" ]; then printf '%s\n' '{"success":true}'; else cv_emit "$CV_RESP"; fi
else
  TMPF=$(mktemp)
  trap 'rm -f "$TMPF"' EXIT
  printf '%s' "$CV_RESP" > "$TMPF"
  python3 - "$TMPF" "$DISPATCH_ID" <<'PY'
import json, sys

raw = open(sys.argv[1], encoding="utf-8").read().strip()
d = {}
if raw:
    try:
        d = json.loads(raw)
    except Exception:
        d = {}
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
print(f"Fila do disparo {sys.argv[2]} populada.")
if isinstance(d, dict):
    if d.get("queueSize") is not None:
        print(f"  envios na fila: {d.get('queueSize')}")
    if d.get("status"):
        print(f"  status:         {d.get('status')}")
print("  Acompanhe o progresso com list-dispatches.sh (sentCount/totalCount).")
PY
fi
