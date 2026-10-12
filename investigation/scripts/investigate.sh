#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Investigation: relatório completo de um agente (somente leitura).
# Uso: investigate.sh <api-key> <agent-id> [days] [limit]
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: investigate.sh <api-key> <agent-id> [days] [limit]

Relatório de investigação de um agente (somente leitura):
  1. configuração do agente (system prompt, modelo, temperatura, tools);
  2. conversas recentes (GET /conversation);
  3. transcrição resumida das mensagens de cada conversa;
  4. próximos passos sugeridos.

Argumentos:
  <api-key>   API key do Chatvolt (ou use CHATVOLT_API_KEY)
  <agent-id>  ID do agente (ou use CHATVOLT_AGENT_ID)
  [days]      janela de dias para as conversas (padrão: 7)
  [limit]     máximo de conversas analisadas, 1..100 (padrão: 10)

Opções:
  -h, --help  mostra esta ajuda

Exemplos:
  investigate.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1 30 20
  CV_JSON=1 investigate.sh "" cmt8mfhzv00h2g9gtypyp54l1 7 5 > relatorio.json

Variáveis:
  CV_API_BASE   base URL alternativa (padrão https://api.chatvolt.ai)
  CV_JSON=1     imprime somente JSON em stdout (diagnósticos em stderr)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
AGENT_ID="${2:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o ID do agente como 2o argumento ou exporte CHATVOLT_AGENT_ID"

DAYS="${3:-7}"
LIMIT="${4:-10}"
case "$DAYS" in ''|*[!0-9]*) cv_die "days precisa ser um inteiro >= 1 (recebido: '$DAYS')" ;; esac
[ "$DAYS" -ge 1 ] || cv_die "days precisa ser >= 1 (recebido: '$DAYS')"
case "$LIMIT" in ''|*[!0-9]*) cv_die "limit precisa ser um inteiro entre 1 e 100 (recebido: '$LIMIT')" ;; esac
if [ "$LIMIT" -lt 1 ] || [ "$LIMIT" -gt 100 ]; then
  cv_die "limit deve estar entre 1 e 100 (recebido: '$LIMIT')"
fi

if SINCE=$(date -u -d "${DAYS} days ago" "+%Y-%m-%dT00:00:00.000Z" 2>/dev/null); then
  :
else
  SINCE=$(date -u -v-"${DAYS}"d "+%Y-%m-%dT00:00:00.000Z")
fi

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

cv_info "1/3 — configuração do agente ${AGENT_ID}..." >&2
cv_get "/agents/${AGENT_ID}"
printf '%s' "$(cv_unwrap "$CV_RESP")" > "${TMPD}/agent.json"
cv_get "/agents/${AGENT_ID}/tools"
printf '%s' "$(cv_unwrap "$CV_RESP")" > "${TMPD}/tools.json"

cv_info "2/3 — conversas desde ${SINCE} (limite ${LIMIT})..." >&2
cv_get "/conversation" -G \
  --data-urlencode "agentId=${AGENT_ID}" \
  --data-urlencode "createdAt=${SINCE}" \
  --data-urlencode "limit=${LIMIT}"
printf '%s' "$(cv_unwrap "$CV_RESP")" > "${TMPD}/convs.json"

cv_info "3/3 — mensagens de cada conversa..." >&2
IDS=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
if isinstance(d,list):
    for c in d:
        cid=c.get("id")
        if cid:
            print(cid)' "${TMPD}/convs.json" 2>/dev/null || true)

while IFS= read -r CID; do
  [ -n "$CID" ] || continue
  cv_get "/conversation/${CID}/messages/20"
  printf '%s' "$(cv_unwrap "$CV_RESP")" > "${TMPD}/msg_${CID}.json"
done <<< "$IDS"

MODE="hum"
[ "$CV_JSON" = "1" ] && MODE="json"

python3 - "$TMPD" "$MODE" "$AGENT_ID" "$SINCE" "$DAYS" "$LIMIT" <<'PY'
import json, os, sys

tmp, mode = sys.argv[1], sys.argv[2]
agent_id, since, days, limit = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]

def load(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default

agent = load(os.path.join(tmp, "agent.json"), {})
tools = load(os.path.join(tmp, "tools.json"), [])
convs = load(os.path.join(tmp, "convs.json"), [])

if isinstance(agent, dict) and "data" in agent and "error" not in agent:
    agent = agent["data"]
if not isinstance(agent, dict):
    agent = {}
if isinstance(tools, dict) and "data" in tools and "error" not in tools:
    tools = tools["data"]
if not isinstance(tools, list):
    tools = []
if not isinstance(convs, list):
    convs = []

conv_data = []
for c in convs:
    if not isinstance(c, dict):
        continue
    cid = c.get("id", "")
    msgs = load(os.path.join(tmp, "msg_%s.json" % cid), {})
    if isinstance(msgs, dict):
        m = msgs.get("messages") or []
    elif isinstance(msgs, list):
        m = msgs
    else:
        m = []
    conv_data.append({"conversation": c, "messages": m})

if mode == "json":
    print(json.dumps({
        "agent": agent,
        "tools": tools,
        "days": int(days),
        "limit": int(limit),
        "since": since,
        "conversations": conv_data,
    }, ensure_ascii=False))
    raise SystemExit(0)

W = 78

def sep(ch="="):
    print(ch * W)

def s(v):
    return "" if v is None else v

def contato(c):
    p = c.get("participantsContacts") or []
    if p and isinstance(p[0], dict):
        return p[0].get("firstName") or p[0].get("name") or p[0].get("phoneNumber") or ""
    return ""

sep()
print("  Relatório de investigação — Chatvolt")
sep()
print("Agente:        %s" % agent_id)
print("Nome:          %s" % s(agent.get("name")))
print("Handle:        %s" % s(agent.get("handle")))
print("Modelo:        %s" % s(agent.get("modelName")))
print("Temperatura:   %s" % s(agent.get("temperature")))
print("Visibilidade:  %s" % s(agent.get("visibility")))
print("Criado em:     %s" % s(agent.get("createdAt")))
print("Atualizado em: %s" % s(agent.get("updatedAt")))

sp = agent.get("systemPrompt")
print()
print("System prompt (%s caracteres):" % (len(sp) if sp else 0))
if sp:
    print(sp)
else:
    print("(nenhum)")

print()
print("Ferramentas (%d):" % len(tools))
for t in tools:
    ttype = t.get("type", "?")
    cfg = t.get("config") or {}
    nome = t.get("name") or cfg.get("name") or ""
    extra = t.get("url") or t.get("datastoreId") or ""
    linha = "  - %s: %s" % (ttype, nome or "(sem nome)")
    if extra:
        linha += "  [%s]" % extra
    if t.get("hasMaximumToolCalls"):
        linha += "  max=%s" % t.get("maximumToolCalls", "")
    print(linha)

print()
sep("-")
print("Conversas desde %s — %d encontrada(s)" % (since, len(conv_data)))
sep("-")
for item in conv_data:
    c = item["conversation"]
    print()
    print("Conversa: %s" % c.get("id", ""))
    print("  canal:     %s    status: %s" % (s(c.get("channel")), s(c.get("status"))))
    print("  criada em: %s    IA ativa: %s" % (s(c.get("createdAt")), "sim" if c.get("isAiEnabled") else "não"))
    print("  contato:   %s" % contato(c))
    msgs = item["messages"]
    shown = 0
    for m in msgs:
        text = (m.get("text") or "").strip()
        if not text:
            continue
        src = m.get("from", "system")
        label = "AGENT" if src == "agent" else ("HUMAN" if src == "human" else src.upper())
        if len(text) > 800:
            text = text[:800] + "... [truncado]"
        print("  [%s] %s" % (label, m.get("createdAt", "")))
        for ln in text.splitlines():
            print("    %s" % ln)
        shown += 1
    if shown == 0:
        print("  (sem mensagens de texto)")

print()
sep()
print("Próximos passos")
sep()
print("1. Comparar o system prompt com as respostas reais das conversas acima.")
print("2. Verificar se as ferramentas configuradas foram realmente usadas.")
print("3. Procurar respostas fora do escopo, inventadas ou sem fonte na base.")
print("4. Revisar o tom e a aderência ao fluxo (saudação, coleta, encerramento).")
print("5. Ajustar prompt/modelo/temperatura (skill chatvolt-prompt-adjust) e retestar.")
print("6. Reexecutar este relatório para comparar o antes/depois.")
sep()
PY
