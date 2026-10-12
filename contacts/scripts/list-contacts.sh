#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — list-contacts
#
# Lista contatos com os filtros de GET /contacts (openapi + contrato verificado
# ao vivo em 2026-10-12): search, tags, conversationStatus, agent, priority,
# crmScenario, crmStep, channel, startDate/endDate, hasEmail/hasPhone.
#
# Paginação: a resposta real é {contacts, count, hasMore, nextCursor}. O
# parâmetro `offset` existe no openapi mas é IGNORADO pela API; a paginação
# efetiva usa o `nextCursor` devolvido (formato "<createdAt>_<id>").
#
# Uso:
#   list-contacts.sh [api-key] [opções]
#
# Opções:
#   --search <termo>          busca por e-mail, telefone, nome ou sobrenome
#   --tag <tag>               filtra por tag (repetível)
#   --agent <id>              filtra por id do agente
#   --status <s>              RESOLVED | UNRESOLVED | HUMAN_REQUESTED
#   --priority <p>            LOW | MEDIUM | HIGH
#   --channel <canal>         website | dashboard | whatsapp | zapi | telegram | instagramDm
#   --crm-scenario <id>       filtra por cenário CRM
#   --crm-step <id>           filtra por etapa CRM
#   --start-date <data ISO>   contatos criados a partir desta data
#   --end-date <data ISO>     contatos criados até esta data
#   --has-email               somente contatos com e-mail
#   --has-phone               somente contatos com telefone
#   --limit <n>               itens por página (1-100, padrão 100)
#   --cursor <cursor>         continua a partir do nextCursor devolvido antes
#   --offset <n>              registros a pular (openapi; a API ignora)
#   --all                     pagina por cursor até o fim
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
list-contacts.sh — lista contatos do Chatvolt (GET /contacts)

Uso:
  list-contacts.sh [api-key] [opções]

Opções:
  --search <termo>          busca por e-mail, telefone, nome ou sobrenome
  --tag <tag>               filtra por tag (repetível)
  --agent <id>              filtra por id do agente
  --status <s>              RESOLVED | UNRESOLVED | HUMAN_REQUESTED
  --priority <p>            LOW | MEDIUM | HIGH
  --channel <canal>         website | dashboard | whatsapp | zapi | telegram | instagramDm
  --crm-scenario <id>       filtra por cenário CRM
  --crm-step <id>           filtra por etapa CRM
  --start-date <data ISO>   contatos criados a partir desta data
  --end-date <data ISO>     contatos criados até esta data
  --has-email               somente contatos com e-mail
  --has-phone               somente contatos com telefone
  --limit <n>               itens por página (1-100, padrão 100)
  --cursor <cursor>         continua a partir do nextCursor devolvido antes
  --offset <n>              registros a pular (openapi; a API ignora)
  --all                     pagina por cursor até o fim
  -h, --help                mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
# 1º argumento posicional = api-key (vence o CHATVOLT_API_KEY do ambiente).
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

SEARCH=""
TAGS=()
AGENT=""
STATUS=""
PRIORITY=""
CHANNEL=""
CRM_SCENARIO=""
CRM_STEP=""
START_DATE=""
END_DATE=""
HAS_EMAIL=""
HAS_PHONE=""
LIMIT="100"
CURSOR=""
OFFSET=""
ALL=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --search)       SEARCH="${2:?--search exige um termo}"; shift 2 ;;
    --tag)          TAGS+=("${2:?--tag exige uma tag}"); shift 2 ;;
    --agent)        AGENT="${2:?--agent exige um id de agente}"; shift 2 ;;
    --status)       STATUS="${2:?--status exige um valor}"; shift 2 ;;
    --priority)     PRIORITY="${2:?--priority exige um valor}"; shift 2 ;;
    --channel)      CHANNEL="${2:?--channel exige um canal}"; shift 2 ;;
    --crm-scenario) CRM_SCENARIO="${2:?--crm-scenario exige um id}"; shift 2 ;;
    --crm-step)     CRM_STEP="${2:?--crm-step exige um id}"; shift 2 ;;
    --start-date)   START_DATE="${2:?--start-date exige uma data ISO}"; shift 2 ;;
    --end-date)     END_DATE="${2:?--end-date exige uma data ISO}"; shift 2 ;;
    --has-email)    HAS_EMAIL="true"; shift ;;
    --has-phone)    HAS_PHONE="true"; shift ;;
    --limit)        LIMIT="${2:?--limit exige um número}"; shift 2 ;;
    --cursor)       CURSOR="${2:?--cursor exige o cursor devolvido pela API}"; shift 2 ;;
    --offset)       OFFSET="${2:?--offset exige um número}"; shift 2 ;;
    --all)          ALL=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um inteiro entre 1 e 100" ;; esac
[ "$LIMIT" -ge 1 ] && [ "$LIMIT" -le 100 ] || cv_die "--limit deve estar entre 1 e 100 (máximo da API)"
if [ -n "$OFFSET" ]; then
  case "$OFFSET" in ''|*[!0-9]*) cv_die "--offset deve ser um inteiro >= 0" ;; esac
fi
if [ -n "$STATUS" ]; then
  case "$STATUS" in
    RESOLVED|UNRESOLVED|HUMAN_REQUESTED) ;;
    *) cv_die "--status inválido: $STATUS (use RESOLVED, UNRESOLVED ou HUMAN_REQUESTED)" ;;
  esac
fi
if [ -n "$PRIORITY" ]; then
  case "$PRIORITY" in
    LOW|MEDIUM|HIGH) ;;
    *) cv_die "--priority inválido: $PRIORITY (use LOW, MEDIUM ou HIGH)" ;;
  esac
fi
if [ -n "$CHANNEL" ]; then
  case "$CHANNEL" in
    website|dashboard|whatsapp|zapi|telegram|instagramDm) ;;
    *) cv_die "--channel inválido: $CHANNEL (website, dashboard, whatsapp, zapi, telegram ou instagramDm)" ;;
  esac
fi

read -r -d '' FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
items = d.get("contacts") or []
if not items:
    print("Nenhum contato encontrado.")
    raise SystemExit
print(f"{'ID':26} {'NOME':22} {'E-MAIL':28} {'TELEFONE':16} CRIADO EM")
for c in items:
    name = " ".join(x for x in (c.get("firstName"), c.get("lastName")) if x) or "-"
    email = c.get("email") or "-"
    phone = c.get("phoneNumber") or "-"
    created = (c.get("createdAt") or "")[:16].replace("T", " ")
    print(f"{c.get('id',''):26} {name[:22]:22} {str(email)[:28]:28} {str(phone)[:16]:16} {created}")
count = d.get("count")
print(f"\nTotal nesta página: {len(items)}" + (f" · total na organização: {count}" if count is not None else ""))
PY

build_args() {
  # $1 = cursor (pode ser vazio)
  local cur="$1"
  ARGS=(--get --data-urlencode "limit=${LIMIT}")
  if [ -n "$OFFSET" ];       then ARGS+=(--data-urlencode "offset=${OFFSET}"); fi
  if [ -n "$SEARCH" ];       then ARGS+=(--data-urlencode "search=${SEARCH}"); fi
  if [ -n "$AGENT" ];        then ARGS+=(--data-urlencode "agent=${AGENT}"); fi
  if [ -n "$STATUS" ];       then ARGS+=(--data-urlencode "conversationStatus=${STATUS}"); fi
  if [ -n "$PRIORITY" ];     then ARGS+=(--data-urlencode "priority=${PRIORITY}"); fi
  if [ -n "$CHANNEL" ];      then ARGS+=(--data-urlencode "channel=${CHANNEL}"); fi
  if [ -n "$CRM_SCENARIO" ]; then ARGS+=(--data-urlencode "crmScenario=${CRM_SCENARIO}"); fi
  if [ -n "$CRM_STEP" ];     then ARGS+=(--data-urlencode "crmStep=${CRM_STEP}"); fi
  if [ -n "$START_DATE" ];   then ARGS+=(--data-urlencode "startDate=${START_DATE}"); fi
  if [ -n "$END_DATE" ];     then ARGS+=(--data-urlencode "endDate=${END_DATE}"); fi
  if [ -n "$HAS_EMAIL" ];    then ARGS+=(--data-urlencode "hasEmail=${HAS_EMAIL}"); fi
  if [ -n "$HAS_PHONE" ];    then ARGS+=(--data-urlencode "hasPhone=${HAS_PHONE}"); fi
  if [ -n "$cur" ];          then ARGS+=(--data-urlencode "cursor=${cur}"); fi
  local t
  for t in "${TAGS[@]}"; do ARGS+=(--data-urlencode "tags=${t}"); done
  return 0
}

# normaliza a página: {contacts, count, hasMore, nextCursor}
page_norm() {
  printf '%s' "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, list):
    d = {"contacts": d}
if not isinstance(d, dict):
    d = {}
print(json.dumps({
    "contacts": d.get("contacts") or [],
    "count": d.get("count"),
    "hasMore": bool(d.get("hasMore")),
    "nextCursor": d.get("nextCursor") or "",
}, ensure_ascii=False))
'
}

if [ "$ALL" = "0" ]; then
  build_args "$CURSOR"
  cv_get "/contacts" "${ARGS[@]}"
  cv_emit "$(page_norm "$(cv_unwrap "$CV_RESP")")" "$FORMATTER"
  exit 0
fi

# --all: pagina pelo nextCursor devolvido pela API até hasMore=false.
PAGES=""
PAGE=0
CURSOR="${CURSOR:-}"
while :; do
  PAGE=$((PAGE + 1))
  build_args "$CURSOR"
  cv_get "/contacts" "${ARGS[@]}"
  NORM=$(page_norm "$(cv_unwrap "$CV_RESP")")
  N=$(printf '%s' "$NORM" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["contacts"]))')
  PAGES+="${NORM}"$'\n'
  NEXT=$(printf '%s' "$NORM" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["nextCursor"] if d["hasMore"] else "")')
  if [ -z "$NEXT" ] || [ "$NEXT" = "$CURSOR" ] || [ "$N" -lt "$LIMIT" ]; then break; fi
  CURSOR="$NEXT"
  if [ "$PAGE" -ge 500 ]; then
    cv_warn "limite de 500 páginas atingido — parando a paginação"
    break
  fi
done

MERGED=$(printf '%s' "$PAGES" | python3 -c '
import json, sys
items, count = [], None
seen = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    if d.get("count") is not None:
        count = d["count"]
    for c in d.get("contacts") or []:
        cid = c.get("id")
        if cid in seen:
            continue
        seen.add(cid)
        items.append(c)
print(json.dumps({"contacts": items, "count": count, "hasMore": False, "nextCursor": ""}, ensure_ascii=False))
')

TOTAL=$(printf '%s' "$MERGED" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["contacts"]))')
cv_warn "paginação concluída: ${TOTAL} contato(s) em ${PAGE} página(s)"
cv_emit "$MERGED" "$FORMATTER"
