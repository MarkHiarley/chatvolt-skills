#!/usr/bin/env bash
set -euo pipefail

# chatvolt tools-update — create-tool.sh
# Cria uma tool em um agente: POST /agents/{agentId}/tools
# (a resposta traz o objeto da tool na raiz; 2xx — 200 ao vivo, 201 no build).

usage() {
  cat <<'EOF'
Uso: create-tool.sh <api-key> <agent-id> <type> <json|--file <path>|id>

Tipos com atalho (o 4º argumento é um id):
  datastore   <datastore-id>   → {"type":"datastore","datastoreId":"..."}
  form        <form-id>        → {"type":"form","formId":"..."}

Tipos HTTP (o 4º argumento é o JSON do corpo, ou --file <path>):
  http        exige config.name, config.description, config.url, config.method
  http-raw    como http, mas marca isRaw=true (raw cURL); exige
              config.name, config.description e (config.url ou config.rawBody)

Qualquer outro tipo (passthrough) aceita o corpo JSON completo:
  quick_reply_buttons, mark_as_resolved, request_human, delayed_responses,
  follow_up_messages, artifact_category_selector, lead_capture, connector,
  agent, channel_transfer

Opções:
  --file <path>   Lê o JSON do corpo de um arquivo.
  -h, --help      Mostra esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_JSON=1           imprime SOMENTE JSON em stdout
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplos:
  create-tool.sh "$KEY" "$AG" datastore cmszh5s6q0fbdvapf36roho4y_v3
  create-tool.sh "$KEY" "$AG" http --file tool.json
  create-tool.sh "$KEY" "$AG" http '{"config":{"name":"Status","description":"Consulta status","url":"https://api.exemplo.com/pedidos/:id","method":"GET"}}'
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
AGENT_ID="${2:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id como 2º argumento ou exporte CHATVOLT_AGENT_ID"
[ "$#" -ge 2 ] || cv_die "informe o tipo e a configuração (use -h para a ajuda)"
shift 2

TYPE="${1:-}"
[ -n "$TYPE" ] || cv_die "informe o tipo da tool (use -h para a ajuda)"
shift 1

PAYLOAD=""
FILE=""
case "${1:-}" in
  --file)
    [ -n "${2:-}" ] || cv_die "--file exige um caminho"
    FILE="$2"; shift 2
    ;;
  "")
    : ;;
  *)
    PAYLOAD="$1"; shift 1
    ;;
esac
[ "$#" -eq 0 ] || cv_die "argumentos extras inesperados: $*"

read_raw() {
  if [ -n "$FILE" ]; then
    [ -f "$FILE" ] || cv_die "arquivo não encontrado: $FILE"
    cat "$FILE"
  else
    [ -n "$PAYLOAD" ] || cv_die "informe a configuração: <json> | --file <path> | <id> (use -h para a ajuda)"
    printf '%s' "$PAYLOAD"
  fi
}

case "$TYPE" in
  datastore|form)
    [ -z "$FILE" ] || cv_die "o tipo '$TYPE' recebe um id, não --file"
    [ -n "$PAYLOAD" ] || cv_die "informe o id: create-tool.sh <api-key> <agent-id> $TYPE <id>"
    BODY=$(python3 - "$TYPE" "$PAYLOAD" <<'PY'
import json, sys
typ, value = sys.argv[1], sys.argv[2]
obj = {"type": typ}
obj["datastoreId" if typ == "datastore" else "formId"] = value
print(json.dumps(obj))
PY
)
    ;;
  http|http-raw)
    RAW=$(read_raw)
    BODY=$(python3 - "$RAW" "$TYPE" <<'PY'
import json, sys
try:
    obj = json.loads(sys.argv[1])
except Exception as e:
    raise SystemExit("JSON inválido: %s" % e)
if not isinstance(obj, dict):
    raise SystemExit("o corpo deve ser um objeto JSON")
cfg = obj.get("config")
if not isinstance(cfg, dict):
    raise SystemExit("o corpo deve ter um objeto 'config'")

def need(field):
    if not cfg.get(field) or not str(cfg[field]).strip():
        raise SystemExit("config.%s é obrigatório" % field)

if sys.argv[2] == "http":
    for f in ("name", "description", "url", "method"):
        need(f)
else:  # http-raw
    for f in ("name", "description"):
        need(f)
    if not (cfg.get("url") or cfg.get("rawBody")):
        raise SystemExit("config.url ou config.rawBody é obrigatório para http-raw")
    obj["isRaw"] = True
    cfg["isRaw"] = True
obj.setdefault("type", sys.argv[2])
print(json.dumps(obj, ensure_ascii=False))
PY
)
    ;;
  *)
    RAW=$(read_raw)
    BODY=$(python3 - "$RAW" "$TYPE" <<'PY'
import json, sys
try:
    obj = json.loads(sys.argv[1])
except Exception as e:
    raise SystemExit("JSON inválido: %s" % e)
if not isinstance(obj, dict):
    raise SystemExit("o corpo deve ser um objeto JSON")
if "type" in obj and obj["type"] != sys.argv[2]:
    raise SystemExit("o campo 'type' do JSON ('%s') difere do tipo informado ('%s')" % (obj["type"], sys.argv[2]))
obj.setdefault("type", sys.argv[2])
print(json.dumps(obj, ensure_ascii=False))
PY
)
    ;;
esac

cv_request POST "/agents/${AGENT_ID}/tools" "$BODY"

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$CV_RESP"
  exit 0
fi

printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
tid = d.get("id", "") if isinstance(d, dict) else ""
print("✅ Tool criada (HTTP 2xx).")
if tid:
    print("   Tool ID: %s" % tid)
else:
    print("   (a resposta não trouxe um id — confira o JSON abaixo)")
print()
print(json.dumps(d, indent=2, ensure_ascii=False))
'
