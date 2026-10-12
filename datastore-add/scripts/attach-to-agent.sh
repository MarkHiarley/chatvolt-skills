#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Conectar uma base de conhecimento (datastore) a um agente, como tool.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./attach-to-agent.sh <api-key> <agent-id> <datastore-id> [--name <n>] [--description <d>]

Cria a tool do tipo "datastore" no agente, para que ele consulte a base.
  POST /agents/{agentId}/tools  {"type":"datastore","datastoreId":"<id>"}
  GET  /agents/{agentId}/tools  (confere o resultado na listagem)

Opções:
  --name <n>          nome da tool (enviado como config.name)
  --description <d>   descrição da tool (enviado como config.description)
  -h, --help          mostra esta ajuda

Observações honestas:
  * A doc não documenta campos de config para tools do tipo datastore e todas as
    tools observadas ao vivo têm config:{} — quem descreve a base para o modelo é o
    pluginName/pluginDescriptionForModel do próprio datastore. Se --name/--description
    não forem aceitos, o script avisa depois de conferir a listagem.
  * Se o agente já tiver uma tool apontando para esta base, o script não cria
    duplicata: informa o id existente e termina com código 0.
  * Conectar uma base dá ao agente acesso a conteúdo novo — o efeito é imediato.
    Para desfazer: tools-update/scripts/delete-tool.sh <api-key> <agent-id> <tool-id>

Exemplos:
  ./attach-to-agent.sh "$CHATVOLT_API_KEY" cmagent123 cmabc123_v3
  ./attach-to-agent.sh "$CHATVOLT_API_KEY" cmagent123 cmabc123_v3 --name "Base FAQ"
  CV_JSON=1 ./attach-to-agent.sh "$CHATVOLT_API_KEY" cmagent123 cmabc123_v3

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

TOOL_NAME=""
TOOL_DESC=""
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --name) [ "$#" -ge 2 ] || { echo "ERRO: --name exige um valor" >&2; exit 1; }; TOOL_NAME="$2"; shift 2 ;;
    --description) [ "$#" -ge 2 ] || { echo "ERRO: --description exige um valor" >&2; exit 1; }; TOOL_DESC="$2"; shift 2 ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
AGENT_ID="${POS[1]:-}"
DS_ID="${POS[2]:-}"
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "informe o <agent-id>"; }
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }

# 1) a base existe? (e qual é o nome que o modelo verá)
cv_get "/datastores/${DS_ID}?limit=1"
DS_NAME=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name") or "")')
[ -n "$DS_NAME" ] || cv_die "não foi possível ler o datastore ${DS_ID}"

# 2) já existe tool apontando para esta base?
cv_get "/agents/${AGENT_ID}/tools"
TOOLS_LIST="$CV_RESP"
EXISTING=$(python3 - "$TOOLS_LIST" "$DS_ID" <<'PY'
import json, sys

tools = json.loads(sys.argv[1])
ds = sys.argv[2]
if isinstance(tools, dict):
    tools = tools.get("data") or []
for t in tools or []:
    if t.get("type") == "datastore" and t.get("datastoreId") == ds:
        print(t.get("id") or "")
        break
PY
)

if [ -n "$EXISTING" ]; then
  if [ "$CV_JSON" = "1" ]; then
    python3 - "$TOOLS_LIST" "$EXISTING" "$DS_ID" "$AGENT_ID" <<'PY'
import json, sys

tools = json.loads(sys.argv[1])
if isinstance(tools, dict):
    tools = tools.get("data") or []
tool = next((t for t in tools if t.get("id") == sys.argv[2]), {})
print(json.dumps({"agentId": sys.argv[4], "datastoreId": sys.argv[3], "created": False,
                  "alreadyConnected": True, "tool": tool}, ensure_ascii=False))
PY
  else
    echo "ℹ️  O agente ${AGENT_ID} já tem uma tool para a base ${DS_NAME} (${DS_ID})."
    echo "   tool id: ${EXISTING} — nada foi criado."
  fi
  exit 0
fi

# 3) cria a tool
BODY=$(python3 - "$DS_ID" "$TOOL_NAME" "$TOOL_DESC" <<'PY'
import json, sys

ds, name, description = sys.argv[1:4]
body = {"type": "datastore", "datastoreId": ds}
cfg = {}
if name:
    cfg["name"] = name
if description:
    cfg["description"] = description
if cfg:
    body["config"] = cfg
print(json.dumps(body, ensure_ascii=False))
PY
)

cv_info "Conectando a base ${DS_NAME} (${DS_ID}) ao agente ${AGENT_ID}..."
cv_request POST "/agents/${AGENT_ID}/tools" "$BODY"
CREATED="$CV_RESP"

# 4) confere na listagem
cv_get "/agents/${AGENT_ID}/tools"
TOOLS_LIST="$CV_RESP"

python3 - "$TOOLS_LIST" "$CREATED" "$DS_ID" "$AGENT_ID" "$DS_NAME" "$TOOL_NAME" "$TOOL_DESC" <<'PY' >&2
import json, sys

tools, created, ds, agent, ds_name, want_name, want_desc = sys.argv[1:8]
tools = json.loads(tools)
if isinstance(tools, dict):
    tools = tools.get("data") or []
created = json.loads(created) if created.strip().startswith(("{", "[")) else {}

tool = None
for t in tools or []:
    if t.get("type") == "datastore" and t.get("datastoreId") == ds:
        tool = t
        break

if tool is None:
    print("❌ A tool não apareceu na listagem do agente — verifique o POST /agents/{id}/tools.")
    raise SystemExit(1)

cfg = tool.get("config") or {}
print("=== Tool datastore no agente ===")
print(f"  tool id:     {tool.get('id')}")
print(f"  type:        {tool.get('type')}")
print(f"  datastoreId: {tool.get('datastoreId')}  ({ds_name})")
print(f"  config:      {json.dumps(cfg, ensure_ascii=False)}")

if want_name or want_desc:
    missing = [k for k, v in (("name", want_name), ("description", want_desc)) if v and k not in cfg]
    if missing:
        print()
        print(f"AVISO: a API não persistiu os campos {', '.join(missing)} em config — "
              "ela não documenta config para tools do tipo 'datastore'.")
        print("       Quem descreve a base para o modelo é pluginName/pluginDescriptionForModel do")
        print("       datastore (ajuste com ./update-datastore.sh).")
PY

if [ "$CV_JSON" = "1" ]; then
  python3 - "$TOOLS_LIST" "$DS_ID" "$AGENT_ID" <<'PY'
import json, sys

tools = json.loads(sys.argv[1])
if isinstance(tools, dict):
    tools = tools.get("data") or []
ds, agent = sys.argv[2], sys.argv[3]
tool = next((t for t in tools if t.get("type") == "datastore" and t.get("datastoreId") == ds), {})
print(json.dumps({"agentId": agent, "datastoreId": ds, "created": True,
                  "alreadyConnected": False, "tool": tool}, ensure_ascii=False))
PY
else
  echo "✅ Base conectada ao agente ${AGENT_ID}."
  echo "   Teste com: agent-test/scripts/send-query.sh <api-key> ${AGENT_ID} \"pergunta sobre a base\""
  echo "   Desfazer:  tools-update/scripts/delete-tool.sh <api-key> ${AGENT_ID} <tool-id>"
fi
