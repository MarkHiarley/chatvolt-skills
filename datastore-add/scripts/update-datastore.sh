#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Atualizar os metadados de uma base de conhecimento (datastore).
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./update-datastore.sh <api-key> <datastore-id> [opções]

Altera nome/descrição/plugin/visibilidade de uma base de conhecimento.
  PATCH /datastores/{id}  ->  objeto atualizado na raiz

Opções:
  --name <nome>              novo nome
  --description <texto>      nova descrição (use "" para apagar)
  --plugin-name <texto>      novo nome curto do plugin (máx. 20 caracteres)
  --plugin-description <t>   nova descrição para humanos do plugin (máx. 90 caracteres)
                             a API prefixa "About " automaticamente: envie só o texto
  --public                   torna a base pública
  --private                  torna a base privada
  -h, --help                 mostra esta ajuda

Mostra o estado atual, o diff do que será enviado e pede confirmação
(CV_YES=1 pula a confirmação). O conteúdo indexado (fontes) não é tocado.

Exemplos:
  ./update-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3 --name "FAQ 2027"
  ./update-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3 --plugin-name "FAQ X" \
      --plugin-description "Perguntas frequentes do produto X"
  CV_JSON=1 CV_YES=1 ./update-datastore.sh "$CHATVOLT_API_KEY" cmabc123_v3 --public

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_YES=1 (pula confirmação) ·
           CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

NAME=""
DESCRIPTION=""
SET_DESC=0
PLUGIN_NAME=""
PLUGIN_DESC=""
PUBLIC=""
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --name) [ "$#" -ge 2 ] || { echo "ERRO: --name exige um valor" >&2; exit 1; }; NAME="$2"; shift 2 ;;
    --description) [ "$#" -ge 2 ] || { echo "ERRO: --description exige um valor" >&2; exit 1; }; DESCRIPTION="$2"; SET_DESC=1; shift 2 ;;
    --plugin-name) [ "$#" -ge 2 ] || { echo "ERRO: --plugin-name exige um valor" >&2; exit 1; }; PLUGIN_NAME="$2"; shift 2 ;;
    --plugin-description) [ "$#" -ge 2 ] || { echo "ERRO: --plugin-description exige um valor" >&2; exit 1; }; PLUGIN_DESC="$2"; shift 2 ;;
    --public) PUBLIC=1; shift ;;
    --private) PUBLIC=0; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DS_ID="${POS[1]:-}"
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$NAME" ] || [ "$SET_DESC" = "1" ] || [ -n "$PLUGIN_NAME" ] || [ -n "$PLUGIN_DESC" ] || [ -n "$PUBLIC" ] \
  || { usage >&2; cv_die "informe ao menos uma alteração (--name, --description, --plugin-name, --plugin-description, --public/--private)"; }

plen=$(python3 -c 'import sys; print(len(sys.argv[1]))' "$PLUGIN_NAME")
dlen=$(python3 -c 'import sys; print(len(sys.argv[1]))' "$PLUGIN_DESC")
[ "$plen" -le 20 ] || cv_die "--plugin-name tem ${plen} caracteres; o limite da API é 20"
[ "$dlen" -le 90 ] || cv_die "--plugin-description tem ${dlen} caracteres; o limite da API é 90"

BODY=$(python3 - "$NAME" "$DESCRIPTION" "$SET_DESC" "$PLUGIN_NAME" "$PLUGIN_DESC" "$PUBLIC" <<'PY'
import json, sys

name, description, set_desc, plugin_name, plugin_desc, public = sys.argv[1:7]
body = {}
if name:
    body["name"] = name
if set_desc == "1":
    body["description"] = description
if plugin_name:
    body["pluginName"] = plugin_name
if plugin_desc:
    body["pluginDescriptionForHumans"] = plugin_desc
if public in ("0", "1"):
    body["isPublic"] = public == "1"
print(json.dumps(body, ensure_ascii=False))
PY
)

cv_get "/datastores/${DS_ID}?limit=1"
BEFORE="$CV_RESP"

python3 - "$BEFORE" "$BODY" <<'PY' >&2
import json, sys

before = json.loads(sys.argv[1])
after = json.loads(sys.argv[2])
labels = {"name": "nome", "description": "descrição", "pluginName": "pluginName",
          "pluginDescriptionForHumans": "pluginDescrição", "isPublic": "isPublic"}
print("=== Estado atual -> novo ===")
for k, v in after.items():
    cur = before.get(k)
    shown = "(vazio)" if v in ("", None) else v
    print(f"  {labels.get(k, k)}: {cur!r} -> {shown!r}")
PY

cv_confirm "Aplicar PATCH /datastores/${DS_ID} com essas alterações?"

cv_request PATCH "/datastores/${DS_ID}" "$BODY"

FORMAT=$(cat <<'PY'
import json, sys

d = json.load(sys.stdin)
print(f"✅ Base atualizada: {d.get('name')} ({d.get('id')})")
print(f"   visibilidade: {d.get('visibility')}   pluginName: {d.get('pluginName')}")
if d.get("pluginDescriptionForHumans"):
    print(f"   pluginDesc:   {d.get('pluginDescriptionForHumans')}")
if d.get("description"):
    print(f"   descrição:    {d.get('description')}")
PY
)

cv_emit "$CV_RESP" "$FORMAT"
