#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Detalhar uma fonte (datasource) de uma base de conhecimento.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./get-source.sh <api-key> <datastore-id> <source-id>

Mostra o estado de indexação de uma fonte.
  GET /datasources/{id}?idstore={datastoreId}  ->  objeto na raiz
  (o parâmetro idstore é obrigatório)

Campos relevantes da resposta: status, nbChunks, nbTokens, textSize, lastSynch,
config.tags, config.custom_id, config.file_url, config.mime_type.

Exemplos:
  ./get-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 cmdef456
  CV_JSON=1 ./get-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 cmdef456

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
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

FORMAT=$(cat <<'PY'
import json, sys

d = json.load(sys.stdin)
cfg = d.get("config") or {}

print("=== Fonte (datasource) ===")
print(f"id:          {d.get('id')}")
print(f"nome:        {d.get('name')}")
print(f"tipo:        {d.get('type')}")
print(f"datastoreId: {d.get('datastoreId')}")
print()
print("=== Indexação ===")
print(f"status:      {d.get('status')}")
print(f"nbChunks:    {d.get('nbChunks')}")
print(f"nbTokens:    {d.get('nbTokens')}")
print(f"textSize:    {d.get('textSize')}")
print(f"nbSynch:     {d.get('nbSynch')}")
print(f"lastSynch:   {d.get('lastSynch')}")
print(f"criado em:   {d.get('createdAt')}")
print(f"atualizado:  {d.get('updatedAt')}")
print()
print("=== Metadados (config) ===")
print(f"tags:        {', '.join(cfg.get('tags') or []) or '(nenhuma)'}")
print(f"custom_id:   {cfg.get('custom_id') or '(nenhum)'}")
print(f"mime_type:   {cfg.get('mime_type') or '-'}")
print(f"fileSize:    {cfg.get('fileSize') if cfg.get('fileSize') is not None else '-'}")
if cfg.get("question"):
    print(f"question:    {cfg.get('question')}")
if cfg.get("answer"):
    print(f"answer:      {cfg.get('answer')}")
print(f"file_url:    {cfg.get('file_url') or '-'}")
if cfg.get("source_url"):
    print(f"source_url:  {cfg.get('source_url')}")
if d.get("datastore"):
    print(f"\nbase:        {d['datastore'].get('name')} ({d['datastore'].get('id')})")

status = d.get("status")
chunks = d.get("nbChunks") or 0
print()
if status == "synched" and chunks > 0:
    print(f"✅ Indexada: {chunks} chunk(s).")
elif status in ("pending", "running"):
    print(f"⏳ Ainda indexando ({status}). Rode este script de novo em alguns segundos.")
elif status == "synched" and chunks == 0:
    print("⚠️  synched com nbChunks=0: a API aceitou a fonte mas não indexou nada.")
    print("    Isso é o sintoma do upload multipart (arquivo .bin de 0 chunks).")
    print("    Reenvie o conteúdo como texto com add-source.sh --text-file/--text.")
else:
    print(f"❌ status '{status}': a fonte não está indexada.")
PY
)

cv_emit "$CV_RESP" "$FORMAT"
