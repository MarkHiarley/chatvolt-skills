#!/usr/bin/env bash
set -euo pipefail

# get-agent.sh — mostra a configuração de um agente Chatvolt.
# Uso: ./get-agent.sh <api-key> <agent-id>
#      CHATVOLT_API_KEY=... ./get-agent.sh <agent-id>   (key pelo ambiente)
# Saída: nome/id/handle/modelo/temperatura/visibilidade, system prompt completo
#        e tabela de tools (id, type, nome/url/datastoreId, máx. de chamadas).

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: get-agent.sh <api-key> <agent-id>
     get-agent.sh <agent-id>            (com CHATVOLT_API_KEY no ambiente)

Mostra a configuração de um agente Chatvolt:
  - nome, id, handle, modelo, temperatura, visibilidade
  - system prompt completo
  - tabela das tools (id, type, nome/url/datastoreId, hasMaximumToolCalls/maximumToolCalls)

Endpoints: GET /agents/{id} + GET /agents/{id}/tools
  (não existe GET /agents/{id}/tools/{toolId} — responde 404)

Variáveis:
  CV_JSON=1         imprime somente JSON em stdout
  CV_API_BASE       base URL alternativa (default https://api.chatvolt.ai)

Exemplos:
  get-agent.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1
  CV_JSON=1 get-agent.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

AGENT_ID="${2:-}"
if [ -n "${CHATVOLT_API_KEY:-}" ] && [ -z "$AGENT_ID" ]; then
  AGENT_ID="${1:-}"   # key veio do ambiente, o argv é o agent-id
  API_KEY=$(cv_req_key)
else
  API_KEY=$(cv_req_key "${1:-}")
fi
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "informe o agent-id"; }

cv_get "/agents/${AGENT_ID}"
AGENT_JSON="$CV_RESP"
cv_get "/agents/${AGENT_ID}/tools"
TOOLS_JSON="$CV_RESP"

cv_info "Agente consultado: ${AGENT_ID}"

if [ "$CV_JSON" = "1" ]; then
  python3 - "$AGENT_JSON" "$TOOLS_JSON" <<'PY'
import json, sys
agent = json.loads(sys.argv[1])
tools = json.loads(sys.argv[2])
if isinstance(tools, dict):
    tools = tools.get("data") or []
print(json.dumps({"agent": agent, "tools": tools}, ensure_ascii=False))
PY
  exit 0
fi

python3 - "$AGENT_JSON" "$TOOLS_JSON" <<'PY'
import json, sys

agent = json.loads(sys.argv[1])
tools = json.loads(sys.argv[2])
if isinstance(tools, dict):
    tools = tools.get("data") or []
if not isinstance(tools, list):
    tools = []

def g(d, *keys, default="—"):
    for k in keys:
        v = d.get(k)
        if v not in (None, ""):
            return v
    return default

print("=" * 60)
print(f"  Agente:        {g(agent, 'name')}")
print(f"  ID:            {g(agent, 'id')}")
print(f"  Handle:        {g(agent, 'handle')}")
print(f"  Modelo:        {g(agent, 'modelName')}")
print(f"  Temperatura:   {g(agent, 'temperature')}")
print(f"  Visibilidade:  {g(agent, 'visibility')}")
print(f"  Criado/atual.: {g(agent, 'createdAt')} / {g(agent, 'updatedAt')}")
print(f"  Tools:         {len(tools)}")
print("=" * 60)

prompt = agent.get("systemPrompt") or ""
print()
if prompt:
    print(f"SYSTEM PROMPT ({len(prompt)} caracteres)")
    print("-" * 60)
    print(prompt)
    print("-" * 60)
else:
    print("SYSTEM PROMPT: (vazio)")

print()
print(f"TOOLS ({len(tools)})")
if not tools:
    print("  (nenhuma tool configurada)")
else:
    header = ("ID", "TIPO", "NOME / URL / DATASTORE", "MÁX. CHAMADAS")
    rows = []
    for t in tools:
        cfg = t.get("config") or {}
        alvo = cfg.get("name") or cfg.get("description") or ""
        if t.get("type") == "http":
            alvo = f"{alvo} — {cfg.get('method', '')} {cfg.get('url', '')}".strip(" —")
        elif t.get("datastoreId"):
            alvo = f"{alvo} [{t['datastoreId']}]".strip()
        elif t.get("formId"):
            alvo = f"{alvo} [form {t['formId']}]".strip()
        elif t.get("serviceProviderId"):
            alvo = f"{alvo} [provider {t['serviceProviderId']}]".strip()
        if not alvo:
            alvo = "—"

        if t.get("hasMaximumToolCalls") is True:
            maximo = f"sim ({t.get('maximumToolCalls', '?')})"
        elif "hasMaximumToolCalls" in t or "maximumToolCalls" in t:
            maximo = f"não ({t.get('maximumToolCalls', '—')})"
        else:
            maximo = "—"
        rows.append((str(t.get("id", "—")), str(t.get("type", "—")), alvo, maximo))

    width = [max(len(header[i]), *(len(r[i]) for r in rows)) for i in range(4)]
    fmt = "  ".join(f"{{:<{w}}}" for w in width)
    print(fmt.format(*header))
    print("  ".join("-" * w for w in width))
    for r in rows:
        print(fmt.format(*r))
PY
