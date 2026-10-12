#!/usr/bin/env bash
set -euo pipefail

# send-query.sh — envia uma query para um agente Chatvolt.
#
# AVISO CRÍTICO: mensagens enviadas pela API são gravadas no histórico REAL da
# conversa. Reutilizar uma conversa existente exige --force explícito.

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: send-query.sh <api-key> <agent-id> <query> [opções]
     send-query.sh <agent-id> <query> [opções]      (com CHATVOLT_API_KEY no ambiente)

Opções:
  --conversation <id>        continua uma conversa existente.
                             OBRIGATÓRIO combinar com --force (senão sai 2).
  --force                    confirma que você aceita gravar a mensagem no
                             histórico real da conversa (só faz sentido com
                             --conversation).
  --temp <0.0-1.0>           sobrescreve a temperatura (temperature)
  --model <nome>             sobrescreve o modelo (modelName)
  --visitor-id <id>          visitorId da conversa
  --contact-id <id>          contactId do contato
  --contact-first-name <n>   contact.firstName
  --contact-email <email>    contact.email
  --contact-phone <tel>      contact.phoneNumber
  --system-prompt <texto>    systemPrompt específico desta query
  --callback-url <url>       callbackURL chamada ao fim da resposta
  --stream                   usa curl -N e imprime os chunks SSE
  -h, --help                 esta ajuda

Sem --conversation o agente cria uma NOVA conversa (recomendado para testes).

Variáveis:
  CHATVOLT_API_KEY   api key (usada se não vier por argv)
  CV_JSON=1          imprime somente JSON em stdout
  CV_API_BASE        base URL alternativa (default https://api.chatvolt.ai)

Códigos de saída: 0 ok · 1 erro de cliente · 2 uso indevido (--conversation sem
--force) · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplos:
  send-query.sh "$KEY" "$AGENT" "Qual o prazo de entrega?"
  send-query.sh "$KEY" "$AGENT" "E para o Rio?" --conversation "$CONV" --force
  send-query.sh "$KEY" "$AGENT" "Resuma em 1 linha" --stream
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

POS=()
CONVERSATION=""
FORCE=0
TEMP=""
MODEL=""
VISITOR_ID=""
CONTACT_ID=""
C_FIRST=""
C_EMAIL=""
C_PHONE=""
SYSTEM_PROMPT=""
CALLBACK_URL=""
STREAM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --conversation)      CONVERSATION="${2:-}"; [ -n "$CONVERSATION" ] || cv_die "--conversation exige um id"; shift 2 ;;
    --force)             FORCE=1; shift ;;
    --temp)              TEMP="${2:-}"; [ -n "$TEMP" ] || cv_die "--temp exige um número entre 0.0 e 1.0"; shift 2 ;;
    --model)             MODEL="${2:-}"; [ -n "$MODEL" ] || cv_die "--model exige um nome"; shift 2 ;;
    --visitor-id)        VISITOR_ID="${2:-}"; shift 2 ;;
    --contact-id)        CONTACT_ID="${2:-}"; shift 2 ;;
    --contact-first-name) C_FIRST="${2:-}"; shift 2 ;;
    --contact-email)     C_EMAIL="${2:-}"; shift 2 ;;
    --contact-phone)     C_PHONE="${2:-}"; shift 2 ;;
    --system-prompt)     SYSTEM_PROMPT="${2:-}"; shift 2 ;;
    --callback-url)      CALLBACK_URL="${2:-}"; shift 2 ;;
    --stream)            STREAM=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    --*)                 usage >&2; cv_die "opção desconhecida: $1" ;;
    *)                   POS+=("$1"); shift ;;
  esac
done

if [ -n "${CHATVOLT_API_KEY:-}" ] && [ "${#POS[@]}" -eq 2 ]; then
  # A key veio do ambiente: os dois posicionais são agent-id e query.
  AGENT_ID="${POS[0]}"
  QUERY="${POS[1]}"
  API_KEY=$(cv_req_key)
elif [ "${#POS[@]}" -eq 3 ]; then
  API_KEY=$(cv_req_key "${POS[0]}")
  AGENT_ID="${POS[1]}"
  QUERY="${POS[2]}"
else
  usage >&2
  cv_die "esperado <api-key> <agent-id> <query> (recebido ${#POS[@]} argumento(s) posicional(is))"
fi

[ -n "$AGENT_ID" ] || { usage >&2; cv_die "informe o agent-id"; }
[ -n "$QUERY" ]    || { usage >&2; cv_die "informe a query"; }

if [ -n "$CONVERSATION" ] && [ "$FORCE" -ne 1 ]; then
  cat >&2 <<EOF
ERRO: --conversation ${CONVERSATION} sem --force.
      Mensagens enviadas pela API são GRAVADAS no histórico real da conversa
      e podem aparecer para o cliente.
      Para continuar mesmo assim, repita com --force. Para testar sem poluir
      histórico, omita --conversation (o agente cria uma conversa nova).
EOF
  exit 2
fi

if [ -n "$TEMP" ]; then
  python3 -c 'import sys; v=float(sys.argv[1]); sys.exit(0 if 0.0 <= v <= 1.0 else 1)' "$TEMP" 2>/dev/null \
    || cv_die "--temp inválido: '$TEMP' (esperado número entre 0.0 e 1.0)"
fi

BODY=$(python3 - "$QUERY" "$CONVERSATION" "$TEMP" "$MODEL" "$VISITOR_ID" "$CONTACT_ID" \
                   "$C_FIRST" "$C_EMAIL" "$C_PHONE" "$SYSTEM_PROMPT" "$CALLBACK_URL" "$STREAM" <<'PY'
import json, sys
(q, conv, temp, model, visitor, contact_id,
 first, email, phone, system_prompt, callback, stream) = sys.argv[1:13]

payload = {"query": q}
if conv:
    payload["conversationId"] = conv
if temp:
    payload["temperature"] = float(temp)
if model:
    payload["modelName"] = model
if visitor:
    payload["visitorId"] = visitor
if contact_id:
    payload["contactId"] = contact_id
contact = {}
if first:
    contact["firstName"] = first
if email:
    contact["email"] = email
if phone:
    contact["phoneNumber"] = phone
if contact:
    payload["contact"] = contact
if system_prompt:
    payload["systemPrompt"] = system_prompt
if callback:
    payload["callbackURL"] = callback
if stream == "1":
    payload["streaming"] = True
print(json.dumps(payload, ensure_ascii=False))
PY
)

FORMATTER='
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
answer = d.get("answer", "(sem resposta)")
print("RESPOSTA")
print("-" * 60)
print(answer)
print("-" * 60)
print("conversationId: " + str(d.get("conversationId", "-")))
print("messageId:      " + str(d.get("messageId", "-")))
print("visitorId:      " + str(d.get("visitorId", "-")))
sources = d.get("sources") or []
print("sources:        " + str(len(sources)))
for s in sources:
    nome = s.get("datasource_name") or s.get("datasource_id") or "?"
    try:
        score = format(float(s.get("score")), ".4f")
    except (TypeError, ValueError):
        score = str(s.get("score", "-"))
    print("  - %s  score=%s  datastore=%s" % (nome, score, s.get("datastore_id", "-")))
'

if [ "$STREAM" -eq 1 ]; then
  BODY_FILE=$(mktemp) ; HDR_FILE=$(mktemp)
  trap 'rm -f "$BODY_FILE" "$HDR_FILE"' EXIT

  if [ "$CV_JSON" = "1" ]; then
    # stdout é reservado ao JSON final: o SSE vai apenas para o arquivo.
    curl -sS -N --max-time "${CV_TIMEOUT:-120}" -D "$HDR_FILE" -X POST \
      -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
      --data-binary "$BODY" \
      "${CV_BASE_URL}/agents/${AGENT_ID}/query" >"$BODY_FILE"
  else
    set -o pipefail
    curl -sS -N --max-time "${CV_TIMEOUT:-120}" -D "$HDR_FILE" -X POST \
      -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
      --data-binary "$BODY" \
      "${CV_BASE_URL}/agents/${AGENT_ID}/query" | tee "$BODY_FILE"
  fi

  STATUS=$(awk 'toupper($1) ~ /^HTTP\// {code=$2} END {print code}' "$HDR_FILE")
  case "$STATUS" in
    2*) : ;;
    429) cv_die "HTTP 429 (rate limit): aguarde e repita — $(head -c 200 "$BODY_FILE")" ;;
    402) cv_die "HTTP 402 (quota): limite mensal do plano atingido" 3 ;;
    401|403) cv_die "HTTP 401/403 (não autorizado): confira a API key" ;;
    5*)  cv_die "HTTP ${STATUS} (erro interno do servidor)" 5 ;;
    "")  cv_die "falha de rede: nenhuma resposta HTTP recebida" 4 ;;
    *)   cv_die "HTTP ${STATUS}: $(head -c 200 "$BODY_FILE")" ;;
  esac

  FINAL=$(python3 - "$BODY_FILE" <<'PY'
import json, sys, urllib.parse
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
obj = None
for line in raw.splitlines():
    line = line.rstrip("\r")
    if not line.startswith("data:"):
        continue
    data = line.split(":", 1)[1].strip()
    if not data or data == "[DONE]":
        continue
    try:
        decoded = urllib.parse.unquote(data)
    except Exception:
        decoded = data
    try:
        parsed = json.loads(decoded)
    except Exception:
        continue
    if isinstance(parsed, dict) and ("answer" in parsed or "conversationId" in parsed):
        obj = parsed
print(json.dumps(obj if obj is not None else {}, ensure_ascii=False))
PY
)

  if [ "$CV_JSON" = "1" ]; then
    printf '%s\n' "$FINAL"
  else
    printf '%s' "$FINAL" | python3 -c "$FORMATTER"
    CONV=$(printf '%s' "$FINAL" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("conversationId","") or "")')
    if [ -n "$CONV" ]; then
      cv_info "Conversa criada/continuada: ${CONV}"
      cv_info "Para apagar a conversa de teste: conversation-cleanup/scripts/delete-conversation.sh <api-key> ${CONV}"
    fi
  fi
  exit 0
fi

cv_request POST "/agents/${AGENT_ID}/query" "$BODY"
cv_emit "$CV_RESP" "$FORMATTER"
CONV=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if isinstance(d, dict) and isinstance(d.get("data"), dict):
    d = d["data"]
print((d or {}).get("conversationId", "") or "")' 2>/dev/null) || CONV=""
if [ -n "$CONV" ]; then
  cv_info "Conversa criada/continuada: ${CONV}"
  cv_info "Para apagar a conversa de teste: conversation-cleanup/scripts/delete-conversation.sh <api-key> ${CONV}"
fi
