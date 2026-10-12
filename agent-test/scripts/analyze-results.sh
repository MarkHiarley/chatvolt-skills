#!/usr/bin/env bash
set -euo pipefail

# analyze-results.sh — monta a transcrição de uma conversa Chatvolt para análise.
#
# Não faz nenhuma avaliação automática ("análise por IA"): busca a conversa real
# na API, imprime o system prompt do agente, a transcrição AGENT/HUMAN, as
# sources (quando fornecidas) e as regras esperadas para comparação manual.

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: analyze-results.sh <api-key> <agent-id> <conversation-id> [opções]
     analyze-results.sh <agent-id> <conversation-id> [opções]   (com CHATVOLT_API_KEY)

Opções:
  -e, --expected "<regras>"   regras que o agente deveria seguir (texto livre;
                              uma regra por linha ou separadas por ';')
  --expected-file <arquivo>   lê as regras de um arquivo
  --sources <json|@arquivo>   sources da resposta (o JSON cru de send-query.sh
                              com CV_JSON=1, ou um arquivo com esse JSON).
                              O endpoint de mensagens NÃO expõe sources.
  --limit <n>                 quantas mensagens pedir à API (default 200)
  -h, --help                  esta ajuda

O que é impresso:
  1. metadados da conversa (status, IA ligada/desligada, contatos);
  2. system prompt do agente (GET /agents/{id});
  3. transcrição cronológica com contagem, marcada como HUMAN / AGENT;
  4. sources usados, quando informados;
  5. as regras esperadas, numeradas.

Nada é avaliado automaticamente: a comparação resposta × regra é sua.

Variáveis: CHATVOLT_API_KEY · CV_JSON=1 (somente JSON em stdout) · CV_API_BASE

Exemplos:
  analyze-results.sh "$KEY" "$AGENT" "$CONV" -e "responder em pt-BR; nunca citar concorrentes"
  CV_JSON=1 analyze-results.sh "$KEY" "$AGENT" "$CONV" --sources @resposta.json
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

POS=()
EXPECTED=""
EXPECTED_FILE=""
SOURCES=""
LIMIT="200"

while [ $# -gt 0 ]; do
  case "$1" in
    -e|--expected)    EXPECTED="${2:-}"; shift 2 ;;
    --expected-file)  EXPECTED_FILE="${2:-}"; [ -n "$EXPECTED_FILE" ] || cv_die "--expected-file exige um caminho"; shift 2 ;;
    --sources)        SOURCES="${2:-}"; [ -n "$SOURCES" ] || cv_die "--sources exige um JSON ou um caminho"; shift 2 ;;
    --limit)          LIMIT="${2:-}"; [ -n "$LIMIT" ] || cv_die "--limit exige um número"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    --*)              usage >&2; cv_die "opção desconhecida: $1" ;;
    *)                POS+=("$1"); shift ;;
  esac
done

if [ -n "${CHATVOLT_API_KEY:-}" ] && [ "${#POS[@]}" -eq 2 ]; then
  AGENT_ID="${POS[0]}"
  CONVERSATION_ID="${POS[1]}"
  API_KEY=$(cv_req_key)
elif [ "${#POS[@]}" -eq 3 ]; then
  API_KEY=$(cv_req_key "${POS[0]}")
  AGENT_ID="${POS[1]}"
  CONVERSATION_ID="${POS[2]}"
else
  usage >&2
  cv_die "esperado <api-key> <agent-id> <conversation-id> (recebido ${#POS[@]} posicional(is))"
fi

case "$LIMIT" in
  ''|*[!0-9]*) usage >&2; cv_die "--limit deve ser um inteiro positivo (recebido '$LIMIT')" ;;
esac
[ "$LIMIT" -gt 0 ] || { usage >&2; cv_die "--limit deve ser maior que zero"; }

if [ -n "$EXPECTED_FILE" ]; then
  [ -f "$EXPECTED_FILE" ] || cv_die "arquivo de regras não encontrado: $EXPECTED_FILE"
  EXPECTED=$(cat "$EXPECTED_FILE")
fi

# extrai a lista de sources de {sources:[...]} / [...] / "caminho" ou "@caminho"
sources_parse() {
  python3 - "$1" <<'PY'
import json, sys, os
raw = sys.argv[1]
if raw.startswith("@"):
    raw = raw[1:]
if os.path.isfile(raw):
    with open(raw, encoding="utf-8") as fh:
        raw = fh.read()
try:
    d = json.loads(raw)
except Exception as exc:
    sys.exit("JSON inválido em --sources: %s" % exc)
if isinstance(d, dict):
    d = d.get("sources") or d.get("data") or []
print(json.dumps(d if isinstance(d, list) else [], ensure_ascii=False))
PY
}

SOURCES_JSON='[]'
SOURCES_INFORMADAS=0
if [ -n "$SOURCES" ]; then
  SOURCES_JSON=$(sources_parse "$SOURCES") || cv_die "não consegui ler as sources informadas ($SOURCES)"
  SOURCES_INFORMADAS=1
fi

cv_get "/agents/${AGENT_ID}"
AGENT_JSON="$CV_RESP"

cv_get "/conversation/${CONVERSATION_ID}/messages/${LIMIT}"
CONV_JSON="$CV_RESP"

if [ "$CV_JSON" = "1" ]; then
  python3 - "$AGENT_JSON" "$CONV_JSON" "$EXPECTED" "$SOURCES_JSON" "$LIMIT" <<'PY'
import json, sys
agent = json.loads(sys.argv[1])
conv = json.loads(sys.argv[2])
expected, sources, limit = sys.argv[3], json.loads(sys.argv[4]), int(sys.argv[5])
if isinstance(conv, dict) and "data" in conv and "error" not in conv:
    conv = conv["data"]
if conv is None:
    print(json.dumps({"error": "conversa nao encontrada (a API respondeu null; ela pode ter sido apagada)"}, ensure_ascii=False))
    raise SystemExit(1)
if not isinstance(conv, dict):
    print(json.dumps({"error": "a resposta de /conversation/{id}/messages nao e um objeto"}, ensure_ascii=False))
    raise SystemExit(1)
msgs = conv.get("messages") or []
msgs = list(reversed(msgs))
out = {
    "conversation": {k: conv.get(k) for k in ("status", "isAiEnabled", "userId", "organizationId", "participantsContacts")},
    "messageCount": len(msgs),
    "possiblyTruncated": len(msgs) >= limit,
    "agent": {"id": agent.get("id"), "name": agent.get("name"), "modelName": agent.get("modelName"),
              "temperature": agent.get("temperature"), "systemPrompt": agent.get("systemPrompt")},
    "messages": msgs,
    "sources": sources,
    "expected": expected,
}
print(json.dumps(out, ensure_ascii=False))
PY
  exit 0
fi

python3 - "$AGENT_JSON" "$CONV_JSON" "$EXPECTED" "$SOURCES_JSON" "$LIMIT" "$CONVERSATION_ID" "$SOURCES_INFORMADAS" <<'PY'
import json, sys

agent = json.loads(sys.argv[1])
conv = json.loads(sys.argv[2])
expected = sys.argv[3]
sources = json.loads(sys.argv[4])
limit = int(sys.argv[5])
conv_id = sys.argv[6]
sources_informadas = sys.argv[7]

if isinstance(conv, dict) and "data" in conv and "error" not in conv:
    conv = conv["data"]
if conv is None:
    print("ERRO: conversa %s não encontrada — a API respondeu null (a conversa pode ter sido apagada)." % conv_id)
    raise SystemExit(1)
if not isinstance(conv, dict):
    print("ERRO: a resposta de /conversation/{id}/messages não é um objeto JSON.")
    raise SystemExit(1)

messages = list(reversed(conv.get("messages") or []))

print("=" * 66)
print("  TRANSCRIÇÃO DA CONVERSA")
print("=" * 66)
print("conversationId: " + conv_id)
print("status:         " + str(conv.get("status", "—")))
print("IA ligada:      " + ("sim" if conv.get("isAiEnabled") else "não"))
contatos = conv.get("participantsContacts") or []
if contatos:
    rotulos = []
    for c in contatos:
        rot = c.get("email") or c.get("phoneNumber") or c.get("name") or "sem identificação"
        rotulos.append(str(rot))
    print("participantes:  " + ", ".join(rotulos))
print("mensagens:      %d" % len(messages))
if len(messages) >= limit:
    print("AVISO: a API devolveu exatamente o limite pedido (%d); pode haver mais." % limit)
print("=" * 66)

agente_nome = agent.get("name", "—")
print()
print("AGENTE")
print("  nome:        %s" % agente_nome)
print("  id:          %s" % agent.get("id", "—"))
print("  modelo:      %s" % agent.get("modelName", "—"))
print("  temperatura: %s" % agent.get("temperature", "—"))
prompt = agent.get("systemPrompt") or ""
print()
if prompt:
    print("SYSTEM PROMPT (%d caracteres)" % len(prompt))
    print("-" * 66)
    print(prompt)
    print("-" * 66)
else:
    print("SYSTEM PROMPT: (vazio)")

print()
print("CONVERSA (ordem cronológica)")
print("-" * 66)
if not messages:
    print("  (nenhuma mensagem encontrada nesta conversa)")
for i, m in enumerate(messages, 1):
    autor = str(m.get("from", "?")).lower()
    rotulo = {"human": "HUMAN", "agent": "AGENT", "user": "HUMAN", "bot": "AGENT"}.get(autor, autor.upper())
    quando = m.get("createdAt", "—")
    texto = m.get("text")
    if texto is None:
        texto = m.get("content") or "(sem texto)"
    print("[%d] %-5s %s" % (i, rotulo, quando))
    for linha in str(texto).splitlines() or [""]:
        print("      " + linha)
    anexos = m.get("attachments") or []
    if anexos:
        print("      (anexos: %d)" % len(anexos))
    print()
print("-" * 66)

print()
print("SOURCES USADOS")
if sources:
    print("-" * 66)
    for s in sources:
        nome = s.get("datasource_name") or s.get("datasource_id") or "?"
        try:
            score = format(float(s.get("score")), ".4f")
        except (TypeError, ValueError):
            score = str(s.get("score", "-"))
        print("  - %s" % nome)
        print("      score=%s  datastore=%s  chunk=%s" % (score, s.get("datastore_id", "-"), s.get("chunk_id", "-")))
    print("-" * 66)
elif sources_informadas == "1":
    print("  (informados, mas a API devolveu uma lista vazia: nenhum trecho usado)")
else:
    print("  (não informados)")
    print("  O endpoint GET /conversation/{id}/messages/{n} não devolve sources.")
    print("  Para incluí-las, passe a resposta bruta da query, por exemplo:")
    print("    CV_JSON=1 send-query.sh <api-key> <agent-id> \"...\" > r.json")
    print("    analyze-results.sh <api-key> <agent-id> <conv-id> --sources @r.json")

print()
print("REGRAS ESPERADAS")
print("-" * 66)
rules = []
for linha in expected.replace(";", "\n").splitlines():
    linha = linha.strip(" \t-*")
    if linha:
        rules.append(linha)
if rules:
    for i, r in enumerate(rules, 1):
        print("  %d. %s" % (i, r))
else:
    print("  (nenhuma regra informada — use -e \"<regras>\" ou --expected-file <arquivo>)")
print("-" * 66)

print()
print("Compare você mesmo cada resposta AGENT com as regras acima.")
print("Nenhuma avaliação automática é feita por este script.")
print("=" * 66)
PY
