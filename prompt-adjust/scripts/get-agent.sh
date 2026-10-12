#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — configuração atual de um agente (leitura)
#
# Uso: ./get-agent.sh <api-key> <agent-id> [--prompt-only] [--no-tools]
#
# Contrato HTTP: GET /agents/{id} e GET /agents/{id}/tools (array na raiz).
# Ver SOURCES.md na raiz do repositório.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: get-agent.sh <api-key> <agent-id> [opções]

Mostra a configuração atual do agente: nome, id, handle, modelo, temperatura,
visibilidade e o system prompt COMPLETO, seguido da tabela de tools.

Argumentos:
  <api-key>    API key do Chatvolt (ou exporte CHATVOLT_API_KEY)
  <agent-id>   ID do agente

Opções:
  --prompt-only   Em modo humano imprime somente o system prompt (para pipe/
                  arquivo). Não tem efeito com CV_JSON=1.
  --no-tools      Não consulta GET /agents/{id}/tools.
  -h, --help      Esta ajuda.

Saída:
  Texto legível em stdout; diagnósticos em stderr.
  Com CV_JSON=1 imprime SOMENTE JSON em stdout:
  {"agent": {...}, "tools": [...]}

Exit codes:
  0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor

Exemplos:
  get-agent.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1
  get-agent.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1 --prompt-only > prompt.txt
  CV_JSON=1 get-agent.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1 | jq .agent.modelName
EOF
}

PROMPT_ONLY=0
SHOW_TOOLS=1
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --prompt-only) PROMPT_ONLY=1; shift ;;
    --no-tools) SHOW_TOOLS=0; shift ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) cv_die "opção desconhecida: $1 (use --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
AGENT_ID="${POS[1]:-}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id: get-agent.sh <api-key> <agent-id>"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

cv_info "Lendo configuração do agente ${AGENT_ID}..." >&2
cv_get "/agents/${AGENT_ID}"
cv_unwrap "$CV_RESP" > "$TMPD/agent.json"

if [ "$SHOW_TOOLS" = "1" ]; then
  cv_get "/agents/${AGENT_ID}/tools"
  cv_unwrap "$CV_RESP" > "$TMPD/tools.json"
else
  printf '[]' > "$TMPD/tools.json"
fi

python3 - "$TMPD/agent.json" "$TMPD/tools.json" > "$TMPD/combined.json" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    agent = json.load(fh)
with open(sys.argv[2], encoding="utf-8") as fh:
    tools = json.load(fh)

if isinstance(agent, dict) and "data" in agent and "error" not in agent:
    agent = agent["data"]
if isinstance(tools, dict) and "data" in tools and "error" not in tools:
    tools = tools["data"]
if not isinstance(tools, list):
    tools = []
print(json.dumps({"agent": agent, "tools": tools}, ensure_ascii=False))
PY

COMBINED=$(cat "$TMPD/combined.json")

if [ "$PROMPT_ONLY" = "1" ] && [ "$CV_JSON" != "1" ]; then
  python3 - "$TMPD/combined.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
sys.stdout.write((d.get("agent") or {}).get("systemPrompt") or "")
sys.stdout.write("\n")
PY
  exit 0
fi

if [ "$SHOW_TOOLS" = "1" ]; then TOOLS_SKIPPED=0; else TOOLS_SKIPPED=1; fi
CV_TOOLS_SKIPPED="$TOOLS_SKIPPED" cv_emit "$COMBINED" '
import json, os, sys

d = json.load(sys.stdin)
a = d.get("agent") or {}
tools = d.get("tools") or []

print("=" * 66)
print("  Nome:         " + str(a.get("name") or "-"))
print("  ID:           " + str(a.get("id") or "-"))
print("  Handle:       " + str(a.get("handle") or "-"))
print("  Modelo:       " + str(a.get("modelName") or "-"))
print("  Temperatura:  " + ("-" if a.get("temperature") is None else str(a.get("temperature"))))
print("  Visibilidade: " + str(a.get("visibility") or "-"))
print("  Idioma:       " + str(a.get("defaultLanguage") or "-"))
print("=" * 66)

prompt = a.get("systemPrompt") or ""
print("")
print("System prompt (" + str(len(prompt)) + " caracteres):")
print("--- inicio do prompt ---")
print(prompt)
print("--- fim do prompt ---")

if not tools:
    print("")
    if os.environ.get("CV_TOOLS_SKIPPED") == "1":
        print("Tools: não consultadas (--no-tools)")
    else:
        print("Tools: nenhuma")
    raise SystemExit

print("")
print("Tools (" + str(len(tools)) + "):")
print("ID".ljust(26) + " " + "TIPO".ljust(28) + " DETALHE")
for t in tools:
    if not isinstance(t, dict):
        continue
    tid = str(t.get("id") or "-")
    ttype = str(t.get("type") or "-")
    cfg = t.get("config") if isinstance(t.get("config"), dict) else {}
    detail = str(cfg.get("name") or t.get("name") or "")
    if t.get("datastoreId"):
        detail = "datastoreId=" + str(t.get("datastoreId"))
    elif t.get("formId"):
        detail = "formId=" + str(t.get("formId"))
    elif cfg.get("url"):
        detail = str(cfg.get("method") or "GET") + " " + str(cfg.get("url"))
    if not detail:
        detail = json.dumps(cfg, ensure_ascii=False)[:120] if cfg else "-"
    extras = []
    if t.get("isRaw"):
        extras.append("isRaw=true")
    if t.get("hasMaximumToolCalls"):
        extras.append("hasMaximumToolCalls=true")
    if t.get("maximumToolCalls") is not None:
        extras.append("maximumToolCalls=" + str(t.get("maximumToolCalls")))
    if extras:
        detail = detail + " [" + ", ".join(extras) + "]"
    print(tid.ljust(26) + " " + ttype.ljust(28) + " " + detail)
'
