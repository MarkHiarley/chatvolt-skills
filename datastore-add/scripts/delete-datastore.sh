#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Deletar uma base de conhecimento (datastore) e todas as suas fontes.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./delete-datastore.sh <api-key> <datastore-id>

APAGA a base de conhecimento e TODAS as fontes dela (irreversível).
  DELETE /datastores/{id}  ->  objeto deletado na raiz

O script mostra o nome e a contagem de fontes e exige confirmação
(CV_YES=1 pula a confirmação; use somente em teste/automação).

Atenção: tools de agentes que apontam para esta base (type "datastore")
passam a referenciar um datastoreId inexistente — remova-as depois com
tools-update/scripts/delete-tool.sh.

Exemplos:
  ./delete-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3
  CV_YES=1 ./delete-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_YES=1 (pula confirmação) ·
           CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DS_ID="${POS[1]:-}"
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }

cv_get "/datastores/${DS_ID}?limit=1"
DETAIL="$CV_RESP"

count=$(python3 - "$DETAIL" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
c = (d.get("_count") or {}).get("datasources")
print(c if isinstance(c, int) else "")
PY
)

if [ -z "$count" ]; then
  cv_get "/datasources/list?datastoreId=${DS_ID}&limit=1"
  count=$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(int((d.get("pagination") or {}).get("total") or 0))
')
fi

python3 - "$DETAIL" "$count" <<'PY' >&2
import json, sys

d = json.loads(sys.argv[1])
print("=== Base a deletar ===")
print(f"  id:     {d.get('id')}")
print(f"  nome:   {d.get('name')}")
print(f"  tipo:   {d.get('type')}   visibilidade: {d.get('visibility')}")
print(f"  fontes: {sys.argv[2]}")
print()
print("AVISO: as fontes acima serão apagadas junto com a base. Não há como desfazer.")
PY

cv_confirm "Deletar a base '$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("name"))' "$DETAIL")' e ${count} fonte(s)?"

cv_request DELETE "/datastores/${DS_ID}"

FORMAT=$(cat <<'PY'
import json, sys

d = json.load(sys.stdin)
if isinstance(d, dict) and d.get("id"):
    print(f"✅ Base deletada: {d.get('name')} ({d.get('id')})")
else:
    print("✅ DELETE aceito pela API. Resposta:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
PY
)

cv_emit "$CV_RESP" "$FORMAT"
