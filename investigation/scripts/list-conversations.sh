#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Investigation: lista conversas de um agente (GET /conversation).
# Somente leitura. Filtros validados localmente antes de chamar a API.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: list-conversations.sh <api-key> <agent-id> [opções]

Lista conversas do agente (GET /conversation). Somente leitura.
Imprime uma tabela com id, canal, status, criação, contato e o marcador
de IA (🤖) quando a conversa está com a IA habilitada.

Argumentos:
  <api-key>   API key do Chatvolt (ou use CHATVOLT_API_KEY)
  <agent-id>  ID do agente (ou use CHATVOLT_AGENT_ID)

Opções:
  --days N               conversas desde N dias atrás (padrão: 7)
  --limit N              itens por página, 1..100 (padrão: 25)
  --status S             RESOLVED | UNRESOLVED | HUMAN_REQUESTED
  --channel C            canal (ex.: whatsapp, telegram, instagram, api, webchat)
  --tag T                filtra por etiqueta da conversa
  --ai enabled|disabled  filtra pelo uso da IA
  --priority P           LOW | MEDIUM | HIGH
  --assignee A           ID do atendente, ou "unassigned"
  --unread                somente conversas com mensagens não lidas
  --all                   pagina por cursor até o fim (--limit = tamanho da página)
  --cursor JSON           cursor inicial: {"lastCreatedAt":"...","lastId":"..."}
  -h, --help              mostra esta ajuda

Observação: a API não filtra por organização na listagem (organizationId não é
parâmetro; ele aparece apenas como campo da conversa).

Exemplos:
  list-conversations.sh "$CHATVOLT_API_KEY" cmt8mfhzv00h2g9gtypyp54l1 --days 30 --limit 100
  list-conversations.sh "" cmt8mfhzv00h2g9gtypyp54l1 --status UNRESOLVED --channel whatsapp
  list-conversations.sh "" cmt8mfhzv00h2g9gtypyp54l1 --all --limit 100 --ai enabled

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
[ $# -gt 0 ] && shift
AGENT_ID=""
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then AGENT_ID="$1"; shift; fi
AGENT_ID="${AGENT_ID:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o ID do agente como 2o argumento ou exporte CHATVOLT_AGENT_ID"

DAYS=7
LIMIT=25
STATUS=""
CHANNEL=""
TAG=""
AI=""
PRIORITY=""
ASSIGNEE=""
UNREAD=0
ALL=0
CURSOR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --days)     [ $# -ge 2 ] || cv_die "faltou valor para --days";     DAYS="$2"; shift 2 ;;
    --limit)    [ $# -ge 2 ] || cv_die "faltou valor para --limit";    LIMIT="$2"; shift 2 ;;
    --status)   [ $# -ge 2 ] || cv_die "faltou valor para --status";   STATUS="$2"; shift 2 ;;
    --channel)  [ $# -ge 2 ] || cv_die "faltou valor para --channel";  CHANNEL="$2"; shift 2 ;;
    --tag)      [ $# -ge 2 ] || cv_die "faltou valor para --tag";      TAG="$2"; shift 2 ;;
    --ai)       [ $# -ge 2 ] || cv_die "faltou valor para --ai";       AI="$2"; shift 2 ;;
    --priority) [ $# -ge 2 ] || cv_die "faltou valor para --priority"; PRIORITY="$2"; shift 2 ;;
    --assignee) [ $# -ge 2 ] || cv_die "faltou valor para --assignee"; ASSIGNEE="$2"; shift 2 ;;
    --cursor)   [ $# -ge 2 ] || cv_die "faltou valor para --cursor";   CURSOR="$2"; shift 2 ;;
    --unread)   UNREAD=1; shift ;;
    --all)      ALL=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use --help)" ;;
  esac
done

# ── Validação dos filtros (evita 400 da API) ────────────────────────────
case "$DAYS" in ''|*[!0-9]*) cv_die "--days precisa ser um inteiro >= 1 (recebido: '$DAYS')" ;; esac
[ "$DAYS" -ge 1 ] || cv_die "--days precisa ser >= 1 (recebido: '$DAYS')"

case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit precisa ser um inteiro entre 1 e 100 (recebido: '$LIMIT')" ;; esac
if [ "$LIMIT" -lt 1 ] || [ "$LIMIT" -gt 100 ]; then
  cv_die "--limit deve estar entre 1 e 100 (máximo da API; recebido: '$LIMIT')"
fi

if [ -n "$STATUS" ]; then
  STATUS=$(printf '%s' "$STATUS" | tr '[:lower:]' '[:upper:]')
  case "$STATUS" in
    RESOLVED|UNRESOLVED|HUMAN_REQUESTED) ;;
    *) cv_die "--status inválido: '$STATUS'. Valores válidos: RESOLVED, UNRESOLVED, HUMAN_REQUESTED" ;;
  esac
fi

if [ -n "$PRIORITY" ]; then
  PRIORITY=$(printf '%s' "$PRIORITY" | tr '[:lower:]' '[:upper:]')
  case "$PRIORITY" in
    LOW|MEDIUM|HIGH) ;;
    *) cv_die "--priority inválido: '$PRIORITY'. Valores válidos: LOW, MEDIUM, HIGH" ;;
  esac
fi

if [ -n "$AI" ]; then
  AI=$(printf '%s' "$AI" | tr '[:upper:]' '[:lower:]')
  case "$AI" in
    enabled|disabled) ;;
    *) cv_die "--ai inválido: '$AI'. Valores válidos: enabled, disabled" ;;
  esac
fi

if [ -n "$CURSOR" ]; then
  printf '%s' "$CURSOR" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert isinstance(d,dict) and "lastCreatedAt" in d and "lastId" in d' 2>/dev/null \
    || cv_die "--cursor inválido: esperado JSON {\"lastCreatedAt\":\"...\",\"lastId\":\"...\"}"
fi

# ── Data inicial (início do dia, UTC) ───────────────────────────────────
if SINCE=$(date -u -d "${DAYS} days ago" "+%Y-%m-%dT00:00:00.000Z" 2>/dev/null); then
  :
else
  SINCE=$(date -u -v-"${DAYS}"d "+%Y-%m-%dT00:00:00.000Z")
fi

# ── Busca uma página (respeitando os filtros) ───────────────────────────
fetch_page() {
  local cursor="$1"
  local -a args=(-G
    --data-urlencode "agentId=${AGENT_ID}"
    --data-urlencode "createdAt=${SINCE}"
    --data-urlencode "limit=${LIMIT}")
  [ -n "$STATUS" ]   && args+=(--data-urlencode "status=${STATUS}")
  [ -n "$CHANNEL" ]  && args+=(--data-urlencode "channel=${CHANNEL}")
  [ -n "$TAG" ]      && args+=(--data-urlencode "tag=${TAG}")
  [ -n "$AI" ]       && args+=(--data-urlencode "ai=${AI}")
  [ -n "$PRIORITY" ] && args+=(--data-urlencode "priority=${PRIORITY}")
  [ -n "$ASSIGNEE" ] && args+=(--data-urlencode "assigneeId=${ASSIGNEE}")
  [ "$UNREAD" = "1" ] && args+=(--data-urlencode "unread=true")
  [ -n "$cursor" ]   && args+=(--data-urlencode "cursor=${cursor}")
  cv_get "/conversation" "${args[@]}"
  cv_unwrap "$CV_RESP"
}

page_count() { python3 -c 'import json,sys
d=json.load(sys.stdin)
print(len(d) if isinstance(d,list) else 0)'; }

next_cursor() { python3 -c 'import json,sys
d=json.load(sys.stdin)
if not isinstance(d,list) or not d:
    print("")
else:
    last=d[-1]
    print(json.dumps({"lastCreatedAt": last.get("createdAt"), "lastId": last.get("id")}, separators=(",",":")))'; }

merge_pages() { python3 -c 'import json,sys
out=[]
for line in sys.stdin:
    line=line.strip()
    if not line:
        continue
    d=json.loads(line)
    if isinstance(d,list):
        out.extend(d)
    elif isinstance(d,dict):
        out.append(d)
print(json.dumps(out, ensure_ascii=False))'; }

cv_info "Conversas do agente ${AGENT_ID} desde ${SINCE} (limite ${LIMIT}/página)" >&2

cursor="$CURSOR"
acc=""
pages=0
while :; do
  page=$(fetch_page "$cursor")
  acc+="${page}"$'\n'
  n=$(printf '%s' "$page" | page_count)
  pages=$((pages + 1))

  if [ "$ALL" != "1" ]; then
    break
  fi
  if [ "$n" -lt "$LIMIT" ]; then
    cv_warn "fim da paginação: última página trouxe ${n} conversa(s) (menos que o limite ${LIMIT})"
    break
  fi
  cursor=$(printf '%s' "$page" | next_cursor)
  if [ -z "$cursor" ]; then
    cv_warn "fim da paginação: não foi possível derivar o próximo cursor"
    break
  fi
  if [ "$pages" -ge 100 ]; then
    cv_warn "fim da paginação: limite de segurança de 100 páginas atingido"
    break
  fi
done

ALL_JSON=$(printf '%s' "$acc" | merge_pages)

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$ALL_JSON"
else
  total=$(printf '%s' "$ALL_JSON" | page_count)
  cv_info "Total: ${total} conversa(s)" >&2
  printf '%s' "$ALL_JSON" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
if isinstance(rows, dict):
    rows = [rows]
if not isinstance(rows, list):
    rows = []

def contato(c):
    p = c.get("participantsContacts") or []
    if p and isinstance(p[0], dict):
        return p[0].get("firstName") or p[0].get("name") or p[0].get("phoneNumber") or p[0].get("email") or ""
    return ""

data = []
for c in rows:
    data.append([
        str(c.get("id", "")),
        str(c.get("channel", "")),
        str(c.get("status", "")),
        str(c.get("createdAt", "")),
        contato(c),
        "🤖" if c.get("isAiEnabled") else "",
    ])

if not data:
    print("(nenhuma conversa encontrada)")
    raise SystemExit(0)

hdr = ["ID", "CANAL", "STATUS", "CRIADA EM", "CONTATO", "IA"]
w = [len(h) for h in hdr]
for r in data:
    for i, v in enumerate(r):
        w[i] = max(w[i], len(v))

def linha(r):
    return "  ".join(v.ljust(w[i]) for i, v in enumerate(r)).rstrip()

print(linha(hdr))
print("  ".join("-" * x for x in w))
for r in data:
    print(linha(r))
'
fi
