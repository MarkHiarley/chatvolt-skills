#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — envia uma query de teste para o agente (POST /agents/{id}/query)
#
# Uso: ./test-query.sh <api-key> <agent-id> <query> [--temp N] [--model M]
#                      [--system-prompt-file <path>]
#
# A resposta vem NA RAIZ: {answer, sources, messageId, conversationId, visitorId}.
# Ver SOURCES.md na raiz do repositório.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: test-query.sh <api-key> <agent-id> <query> [opções]

Envia uma query de teste e mostra a resposta do agente, as fontes usadas e os
identificadores criados.

Atenção: uma query SEM conversationId cria uma CONVERSA REAL (canal api) no
histórico da organização. O script imprime o conversationId para você apagar
depois com a skill `conversation-cleanup` (delete-conversation.sh).

Argumentos:
  <api-key>    API key do Chatvolt (ou exporte CHATVOLT_API_KEY)
  <agent-id>   ID do agente
  <query>      Pergunta enviada ao agente

Opções:
  --temp <n>                  Sobrescreve a temperatura (0.0-1.0) só nesta query
  --model <m>                 Sobrescreve o modelo só nesta query
                              (valide o nome com list-models.sh)
  --system-prompt-file <path> Sobrescreve o system prompt só nesta query
  -h, --help                  Esta ajuda

Saída:
  Resposta em stdout (com CV_JSON=1, SOMENTE o JSON cru da resposta);
  diagnósticos/identificadores em stderr.

Exit codes:
  0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor

Exemplos:
  test-query.sh "$CHATVOLT_API_KEY" <agent-id> 'Qual o prazo de entrega?'
  test-query.sh "$CHATVOLT_API_KEY" <agent-id> 'Olá' --model gpt_41 --temp 0.2
EOF
}

TEMP_ARG=''
MODEL_ARG=''
SP_FILE=''
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --temp) shift; TEMP_ARG="${1:-}"; [ -n "$TEMP_ARG" ] || cv_die "--temp exige um valor"; shift ;;
    --temp=*) TEMP_ARG="${1#--temp=}"; shift ;;
    --model) shift; MODEL_ARG="${1:-}"; [ -n "$MODEL_ARG" ] || cv_die "--model exige um valor"; shift ;;
    --model=*) MODEL_ARG="${1#--model=}"; shift ;;
    --system-prompt-file) shift; SP_FILE="${1:-}"; [ -n "$SP_FILE" ] || cv_die "--system-prompt-file exige um caminho"; shift ;;
    --system-prompt-file=*) SP_FILE="${1#--system-prompt-file=}"; shift ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) cv_die "opção desconhecida: $1 (use --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
AGENT_ID="${POS[1]:-}"
QUERY="${POS[2]:-}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id: test-query.sh <api-key> <agent-id> <query>"
[ -n "$QUERY" ] || cv_die "informe a query: test-query.sh <api-key> <agent-id> <query>"

if [ -n "$TEMP_ARG" ]; then
  python3 - "$TEMP_ARG" <<'PY' || cv_die "temperatura inválida: '${TEMP_ARG}' — use um número entre 0.0 e 1.0"
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    sys.stderr.write("valor não numérico\n")
    raise SystemExit(1)
if value < 0.0 or value > 1.0:
    sys.stderr.write("valor fora da faixa 0.0-1.0\n")
    raise SystemExit(1)
PY
fi

if [ -n "$SP_FILE" ] && [ ! -f "$SP_FILE" ]; then
  cv_die "arquivo de system prompt não encontrado: ${SP_FILE}"
fi

BODY=$(python3 - "$QUERY" "$TEMP_ARG" "$MODEL_ARG" "$SP_FILE" <<'PY'
import json, sys

query, temp, model, sp_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
body = {"query": query, "streaming": False}
if temp:
    body["temperature"] = float(temp)
if model:
    body["modelName"] = model
if sp_file:
    with open(sp_file, encoding="utf-8", errors="replace") as fh:
        body["systemPrompt"] = fh.read()
print(json.dumps(body))
PY
)

echo "Enviando query para o agente ${AGENT_ID}..." >&2
[ -n "$TEMP_ARG" ] && echo "  temperatura: ${TEMP_ARG}" >&2
[ -n "$MODEL_ARG" ] && echo "  modelo:      ${MODEL_ARG}" >&2
[ -n "$SP_FILE" ] && echo "  system prompt: ${SP_FILE}" >&2

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

cv_request POST "/agents/${AGENT_ID}/query" "$BODY"
printf '%s' "$CV_RESP" > "$TMPD/resposta.json"

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$(cat "$TMPD/resposta.json")"
  exit 0
fi

python3 - "$TMPD/resposta.json" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    raw = json.load(fh)
d = raw
if isinstance(raw, dict) and "answer" not in raw and isinstance(raw.get("data"), dict):
    d = raw["data"]

if not isinstance(d, dict):
    print(json.dumps(raw, ensure_ascii=False, indent=2))
    raise SystemExit

print("=== RESPOSTA DO AGENTE ===")
print(d.get("answer") if d.get("answer") is not None else json.dumps(d, ensure_ascii=False))
print("=== FIM DA RESPOSTA ===")

sources = d.get("sources")
print("")
if isinstance(sources, list) and sources:
    print("Fontes usadas (" + str(len(sources)) + "):")
    for s in sources:
        if isinstance(s, dict):
            nome = s.get("datasource_name") or s.get("name") or s.get("title") or "?"
            score = s.get("score")
            extra = ("  score=" + str(score)) if score is not None else ""
            print("  - " + str(nome) + extra)
        else:
            print("  - " + str(s))
else:
    print("Fontes usadas: nenhuma")

print("")
if d.get("conversationId"):
    print("Conversa criada (canal api): " + str(d.get("conversationId")))
    print("  Apague depois com: conversation-cleanup/scripts/delete-conversation.sh <api-key> " + str(d.get("conversationId")))
else:
    print("Conversa: nenhum conversationId retornado")
if d.get("messageId"):
    print("Mensagem: " + str(d.get("messageId")))
if d.get("visitorId"):
    print("Visitante: " + str(d.get("visitorId")))
PY
