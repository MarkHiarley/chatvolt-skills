#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Deletar uma fonte (datasource) de uma base de conhecimento.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./delete-source.sh <api-key> <datastore-id> <source-id>

APAGA uma fonte da base de conhecimento (irreversível).
  DELETE /datasources/{id}  ->  objeto deletado na raiz

O script mostra a fonte (nome, tipo, status, chunks) e exige confirmação
(CV_YES=1 pula a confirmação; use somente em teste/automação).

Exemplos:
  ./delete-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 cmdef456
  CV_YES=1 ./delete-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 cmdef456

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
SRC_ID="${POS[2]:-}"
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$SRC_ID" ] || { usage >&2; cv_die "informe o <source-id>"; }

cv_get "/datasources/${SRC_ID}?idstore=${DS_ID}"
DETAIL="$CV_RESP"

python3 - "$DETAIL" <<'PY' >&2
import json, sys

d = json.loads(sys.argv[1])
cfg = d.get("config") or {}
print("=== Fonte a deletar ===")
print(f"  id:        {d.get('id')}")
print(f"  nome:      {d.get('name')}")
print(f"  tipo:      {d.get('type')}   status: {d.get('status')}")
print(f"  chunks:    {d.get('nbChunks')}   tokens: {d.get('nbTokens')}")
print(f"  tags:      {', '.join(cfg.get('tags') or []) or '(nenhuma)'}")
print(f"  custom_id: {cfg.get('custom_id') or '(nenhum)'}")
print()
print("AVISO: a fonte e os trechos indexados serão apagados. Não há como desfazer.")
PY

cv_confirm "Deletar a fonte $(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("name"))' "$DETAIL") (${SRC_ID})?"

cv_request DELETE "/datasources/${SRC_ID}"

FORMAT=$(cat <<'PY'
import json, sys

d = json.load(sys.stdin)
if isinstance(d, dict) and d.get("id"):
    print(f"✅ Fonte deletada: {d.get('name')} ({d.get('id')})")
else:
    print("✅ DELETE aceito pela API. Resposta:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
PY
)

cv_emit "$CV_RESP" "$FORMAT"
