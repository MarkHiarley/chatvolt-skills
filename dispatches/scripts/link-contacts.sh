#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Vínculo entre um disparo e uma lista de contatos.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./link-contacts.sh <api-key> --dispatch <dispatchId> --list <contactListId> [--exclude]

Cria/atualiza o vínculo entre um disparo e uma lista de contatos.
  POST /dispatches/contacts/link  {"dispatchId","contactListId","isExcluded"}

Sem --exclude o vínculo é de INCLUSÃO (isExcluded=false); com --exclude a lista
passa a ser de EXCLUSÃO do disparo.

Opções:
  --dispatch ID   id do disparo (obrigatório)
  --list ID       id da lista de contatos (obrigatório)
  --exclude       marca a lista como excluída do disparo
  -h, --help      mostra esta ajuda

Exemplos:
  ./link-contacts.sh "$CHATVOLT_API_KEY" --dispatch "$DISPATCH_ID" --list "$LIST_ID"
  ./link-contacts.sh "$CHATVOLT_API_KEY" --dispatch "$DISPATCH_ID" --list "$OPT_OUT" --exclude

Observação: o vínculo não envia mensagens. Os envios começam quando a fila é
populada (populate-queue.sh).

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

DISPATCH_ID=""; LIST_ID=""; EXCLUDE=0
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dispatch) [ "$#" -ge 2 ] || { echo "ERRO: --dispatch exige um valor" >&2; exit 1; }; DISPATCH_ID="$2"; shift 2 ;;
    --list) [ "$#" -ge 2 ] || { echo "ERRO: --list exige um valor" >&2; exit 1; }; LIST_ID="$2"; shift 2 ;;
    --exclude) EXCLUDE=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
[ -n "$DISPATCH_ID" ] || cv_die "--dispatch é obrigatório (id do disparo)"
[ -n "$LIST_ID" ] || cv_die "--list é obrigatório (id da lista de contatos)"

BODY=$(python3 - "$DISPATCH_ID" "$LIST_ID" "$EXCLUDE" <<'PY'
import json, sys
dispatch_id, list_id, exclude = sys.argv[1:4]
print(json.dumps({"dispatchId": dispatch_id, "contactListId": list_id,
                  "isExcluded": exclude == "1"}, ensure_ascii=False))
PY
)

cv_request POST "/dispatches/contacts/link" "$BODY"

if [ "$CV_JSON" = "1" ]; then
  if [ -z "$CV_RESP" ]; then printf '%s\n' '{"success":true}'; else cv_emit "$CV_RESP"; fi
else
  TMPF=$(mktemp)
  trap 'rm -f "$TMPF"' EXIT
  printf '%s' "$CV_RESP" > "$TMPF"
  python3 - "$TMPF" "$DISPATCH_ID" "$LIST_ID" "$EXCLUDE" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read().strip()
msg = ""
if raw:
    try:
        d = json.loads(raw)
        if isinstance(d, dict):
            msg = d.get("message") or ""
    except Exception:
        msg = raw
kind = "exclusão" if sys.argv[4] == "1" else "inclusão"
print(msg or f"Lista {sys.argv[3]} vinculada ao disparo {sys.argv[2]}.")
print(f"  vínculo: {kind}")
PY
fi
