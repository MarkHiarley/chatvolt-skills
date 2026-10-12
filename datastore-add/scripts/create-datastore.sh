#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Criar uma base de conhecimento (datastore).
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./create-datastore.sh <api-key> --name <nome> [opções]

Cria uma base de conhecimento vazia.
  POST /datastores  ->  objeto na raiz (o id novo termina em "_v3")

Opções:
  --name <nome>                (obrigatório) nome visível da base
  --description <texto>        descrição da base
  --plugin-name <texto>        nome curto do plugin (máx. 20 caracteres)
  --plugin-description <t>     descrição para humanos do plugin (máx. 90 caracteres)
                               a API prefixa "About " automaticamente: envie só o texto
  --public                     torna a base pública (padrão: privada)
  -h, --help                   mostra esta ajuda

Exemplos:
  ./create-datastore.sh "$CHATVOLT_API_KEY" --name "Base Produto X"
  ./create-datastore.sh "$CHATVOLT_API_KEY" --name "Base FAQ" \
      --description "Perguntas frequentes" --plugin-name "FAQ X" \
      --plugin-description "Perguntas frequentes do produto X"
  CV_JSON=1 ./create-datastore.sh "$CHATVOLT_API_KEY" --name "Base Teste"

Depois de criar: use ./add-source.sh para enviar conteúdo e
./attach-to-agent.sh para conectar a base ao agente.

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

NAME=""
DESCRIPTION=""
PLUGIN_NAME=""
PLUGIN_DESC=""
PUBLIC=0
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --name) [ "$#" -ge 2 ] || { echo "ERRO: --name exige um valor" >&2; exit 1; }; NAME="$2"; shift 2 ;;
    --description) [ "$#" -ge 2 ] || { echo "ERRO: --description exige um valor" >&2; exit 1; }; DESCRIPTION="$2"; shift 2 ;;
    --plugin-name) [ "$#" -ge 2 ] || { echo "ERRO: --plugin-name exige um valor" >&2; exit 1; }; PLUGIN_NAME="$2"; shift 2 ;;
    --plugin-description) [ "$#" -ge 2 ] || { echo "ERRO: --plugin-description exige um valor" >&2; exit 1; }; PLUGIN_DESC="$2"; shift 2 ;;
    --public) PUBLIC=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
[ -n "$NAME" ] || { usage >&2; cv_die "informe --name <nome>"; }

plen=$(python3 -c 'import sys; print(len(sys.argv[1]))' "$PLUGIN_NAME")
dlen=$(python3 -c 'import sys; print(len(sys.argv[1]))' "$PLUGIN_DESC")
[ "$plen" -le 20 ] || cv_die "--plugin-name tem ${plen} caracteres; o limite da API é 20"
[ "$dlen" -le 90 ] || cv_die "--plugin-description tem ${dlen} caracteres; o limite da API é 90"

BODY=$(python3 - "$NAME" "$DESCRIPTION" "$PLUGIN_NAME" "$PLUGIN_DESC" "$PUBLIC" <<'PY'
import json, sys

name, description, plugin_name, plugin_desc, public = sys.argv[1:6]
body = {"name": name, "type": "qdrant"}
if description:
    body["description"] = description
if plugin_name:
    body["pluginName"] = plugin_name
if plugin_desc:
    body["pluginDescriptionForHumans"] = plugin_desc
if public == "1":
    body["isPublic"] = True
print(json.dumps(body, ensure_ascii=False))
PY
)

cv_request POST "/datastores" "$BODY"

FORMAT=$(cat <<'PY'
import json, sys

d = json.load(sys.stdin)
if not isinstance(d, dict) or not d.get("id"):
    print("❌ Resposta inesperada ao criar a base:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
    raise SystemExit(1)

print(f"✅ Base de conhecimento criada: {d.get('name')}")
print(f"   id:        {d.get('id')}")
print(f"   tipo:      {d.get('type')}   visibilidade: {d.get('visibility')}")
print(f"   pluginName: {d.get('pluginName')}")
if d.get("pluginDescriptionForHumans"):
    print(f"   pluginDesc: {d.get('pluginDescriptionForHumans')}")
print()
print("Próximos passos:")
print(f"  ./add-source.sh <api-key> {d.get('id')} --text-file manual.md --name manual.md")
print(f"  ./query-base.sh <api-key> {d.get('id')} \"pergunta de prova\"")
print(f"  ./attach-to-agent.sh <api-key> <agent-id> {d.get('id')}")
PY
)

cv_emit "$CV_RESP" "$FORMAT"
