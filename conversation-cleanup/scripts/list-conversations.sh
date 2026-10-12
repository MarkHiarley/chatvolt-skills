#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — list-conversations
#
# Lista conversas usando os filtros VÁLIDOS de GET /conversation
# (agentId, channel, createdAt, endDate, status, limit, cursor).
# `organizationId` NÃO é parâmetro desta rota — ele só aparece na resposta.
#
# Uso:
#   list-conversations.sh [api-key] [opções]
#
# Opções:
#   --agent <id>        filtra por agente (agentId)
#   --channel <canal>   filtra por canal (api, whatsapp, slack, ...)
#   --days <n>          conversas criadas nos últimos N dias (createdAt)
#   --created-at <dia>  data inicial ISO (YYYY-MM-DD); sobrepõe --days
#   --end-date <dia>    data final ISO (YYYY-MM-DD) (endDate)
#   --status <status>   RESOLVED | UNRESOLVED | HUMAN_REQUESTED
#   --limit <n>         itens por página (1-100, padrão 25)
#   --cursor <json>     cursor {"lastCreatedAt","lastId"} para continuar de onde parou
#   --all               pagina por cursor até o fim
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
list-conversations.sh — lista conversas do Chatvolt (GET /conversation)

Uso:
  list-conversations.sh [api-key] [opções]

Opções:
  --agent <id>        filtra por agente (agentId)
  --channel <canal>   filtra por canal (api, whatsapp, slack, ...)
  --days <n>          conversas criadas nos últimos N dias (createdAt)
  --created-at <dia>  data inicial ISO (YYYY-MM-DD); sobrepõe --days
  --end-date <dia>    data final ISO (YYYY-MM-DD) (endDate)
  --status <status>   RESOLVED | UNRESOLVED | HUMAN_REQUESTED
  --limit <n>         itens por página (1-100, padrão 25)
  --cursor <json>     cursor {"lastCreatedAt","lastId"} da página anterior
  --all               pagina por cursor até o fim
  -h, --help          mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ -z "${CHATVOLT_API_KEY:-}" ] && [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

AGENT=""
CHANNEL=""
DAYS=""
CREATED_AT=""
END_DATE=""
STATUS=""
LIMIT="25"
CURSOR=""
ALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)    AGENT="${2:?--agent exige um id de agente}"; shift 2 ;;
    --channel)  CHANNEL="${2:?--channel exige um canal}"; shift 2 ;;
    --days)     DAYS="${2:?--days exige um número}"; shift 2 ;;
    --created-at) CREATED_AT="${2:?--created-at exige uma data YYYY-MM-DD}"; shift 2 ;;
    --end-date) END_DATE="${2:?--end-date exige uma data YYYY-MM-DD}"; shift 2 ;;
    --status)   STATUS="${2:?--status exige um valor}"; shift 2 ;;
    --limit)    LIMIT="${2:?--limit exige um número}"; shift 2 ;;
    --cursor)   CURSOR="${2:?--cursor exige o JSON do cursor}"; shift 2 ;;
    --all)      ALL=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

case "$LIMIT" in
  ''|*[!0-9]*) cv_die "--limit deve ser um inteiro entre 1 e 100" ;;
esac
[ "$LIMIT" -ge 1 ] && [ "$LIMIT" -le 100 ] || cv_die "--limit deve estar entre 1 e 100 (máximo da API)"

if [ -n "$DAYS" ]; then
  case "$DAYS" in ''|*[!0-9]*) cv_die "--days deve ser um inteiro positivo" ;; esac
  CREATED_AT=$(date -d "-${DAYS} days" +%F)
fi

if [ -n "$STATUS" ]; then
  case "$STATUS" in
    RESOLVED|UNRESOLVED|HUMAN_REQUESTED) ;;
    *) cv_die "--status inválido: $STATUS (use RESOLVED, UNRESOLVED ou HUMAN_REQUESTED)" ;;
  esac
fi

read -r -d '' FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if not d:
    print("Nenhuma conversa encontrada.")
    raise SystemExit
print(f"{'ID':26} {'CANAL':9} {'STATUS':15} {'CRIADA EM':17} {'CONTATO':20} IA")
for c in d:
    cs = c.get("participantsContacts") or []
    name = "-"
    if cs:
        name = cs[0].get("firstName") or cs[0].get("email") or cs[0].get("phoneNumber") or "-"
    ai = "sim" if c.get("isAiEnabled") else "-"
    created = (c.get("createdAt") or "")[:16].replace("T", " ")
    cid = c.get("id", "")
    chan = c.get("channel", "")
    st = c.get("status", "")
    print(f"{cid:26} {chan:9} {st:15} {created:17} {str(name)[:20]:20} {ai}")
print(f"\nTotal: {len(d)}")
PY

build_args() {
  # $1 = cursor (pode ser vazio)
  local cur="$1"
  ARGS=(--get --data-urlencode "limit=${LIMIT}")
  if [ -n "$AGENT" ];      then ARGS+=(--data-urlencode "agentId=${AGENT}"); fi
  if [ -n "$CHANNEL" ];    then ARGS+=(--data-urlencode "channel=${CHANNEL}"); fi
  if [ -n "$CREATED_AT" ]; then ARGS+=(--data-urlencode "createdAt=${CREATED_AT}"); fi
  if [ -n "$END_DATE" ];   then ARGS+=(--data-urlencode "endDate=${END_DATE}"); fi
  if [ -n "$STATUS" ];     then ARGS+=(--data-urlencode "status=${STATUS}"); fi
  if [ -n "$cur" ];        then ARGS+=(--data-urlencode "cursor=${cur}"); fi
  return 0
}

last_cursor() {
  printf '%s' "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
c = d[-1]
print(json.dumps({"lastCreatedAt": c.get("createdAt"), "lastId": c.get("id")}, separators=(",", ":")))
'
}

if [ "$ALL" = "0" ]; then
  build_args "$CURSOR"
  cv_get "/conversation" "${ARGS[@]}"
  MERGED=$(cv_unwrap "$CV_RESP")
  cv_emit "$MERGED" "$FORMATTER"
  exit 0
fi

# --all: pagina por cursor até o fim.
PAGES=""
PAGE=0
CURSOR="${CURSOR:-}"
while :; do
  PAGE=$((PAGE + 1))
  build_args "$CURSOR"
  cv_get "/conversation" "${ARGS[@]}"
  NORM=$(cv_unwrap "$CV_RESP")
  N=$(printf '%s' "$NORM" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
  PAGES+="${NORM}"$'\n'
  if [ "$N" -lt "$LIMIT" ]; then break; fi
  CURSOR=$(last_cursor "$NORM")
  if [ "$PAGE" -ge 200 ]; then
    cv_warn "limite de 200 páginas atingido — parando a paginação"
    break
  fi
done

MERGED=$(printf '%s' "$PAGES" | python3 -c '
import json, sys
all_items = []
for line in sys.stdin:
    line = line.strip()
    if line:
        all_items.extend(json.loads(line))
seen = set()
out = []
for c in all_items:
    cid = c.get("id")
    if cid in seen:
        continue
    seen.add(cid)
    out.append(c)
print(json.dumps(out, ensure_ascii=False))
')

TOTAL=$(printf '%s' "$MERGED" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
cv_warn "paginação concluída: ${TOTAL} conversa(s) em ${PAGE} página(s)"
cv_emit "$MERGED" "$FORMATTER"
