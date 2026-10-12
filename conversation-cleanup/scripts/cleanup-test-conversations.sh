#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — cleanup-test-conversations
#
# Remove conversas de TESTE (canal "api") de uma vez. Nunca toca em
# conversas de canais reais (whatsapp, slack, messenger, e-mail, ...).
#
# Uso:
#   cleanup-test-conversations.sh [api-key] [opções]
#
# Opções:
#   --agent <id>   restringe a um agente (agentId)
#   --days <n>     somente conversas criadas nos últimos N dias
#   --yes, -y      pula as confirmações (equivalente a CV_YES=1)
#   -h, --help
#
# A listagem é exaustiva (paginação por cursor). Antes de deletar, o script
# exige DUAS confirmações manuais (digitar "sim" duas vezes), puláveis apenas
# com CV_YES=1 / --yes.
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1           pula as confirmações
#   CV_DELETE_PACE     segundos de pausa entre DELETEs (default 1) — evita o
#                      limite de 60 req/min; 429 é reprocessado com backoff
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
cleanup-test-conversations.sh — apaga todas as conversas de teste (canal api)

Uso:
  cleanup-test-conversations.sh [api-key] [opções]

Opções:
  --agent <id>   restringe a um agente (agentId)
  --days <n>     somente conversas criadas nos últimos N dias
  --yes, -y      pula as confirmações (equivalente a CV_YES=1)
  -h, --help     mostra esta ajuda

Somente o canal "api" é afetado. Conversas reais NUNCA são tocadas.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_YES=1            pula as confirmações
  CV_DELETE_PACE      pausa entre DELETEs em segundos (default 1)
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
# 1º argumento posicional = api-key (vence o CHATVOLT_API_KEY do ambiente,
# igual às outras skills); a env var é só o atalho quando ele é omitido.
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

AGENT=""
DAYS=""
YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)   AGENT="${2:?--agent exige um id de agente}"; shift 2 ;;
    --days)    DAYS="${2:?--days exige um número}"; shift 2 ;;
    --yes|-y)  YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

CREATED_AT=""
if [ -n "$DAYS" ]; then
  case "$DAYS" in ''|*[!0-9]*) cv_die "--days deve ser um inteiro positivo" ;; esac
  CREATED_AT=$(date -d "-${DAYS} days" +%F)
fi

if [ "$YES" = "1" ]; then export CV_YES=1; fi

PAGE_LIMIT=100

build_args() {
  local cur="$1"
  ARGS=(--get --data-urlencode "limit=${PAGE_LIMIT}")
  ARGS+=(--data-urlencode "channel=api")
  if [ -n "$AGENT" ];      then ARGS+=(--data-urlencode "agentId=${AGENT}"); fi
  if [ -n "$CREATED_AT" ]; then ARGS+=(--data-urlencode "createdAt=${CREATED_AT}"); fi
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

cv_info "Buscando conversas de teste (canal api) com paginação exaustiva..."

PAGES=""
PAGE=0
CURSOR=""
while :; do
  PAGE=$((PAGE + 1))
  build_args "$CURSOR"
  cv_get "/conversation" "${ARGS[@]}"
  NORM=$(cv_unwrap "$CV_RESP")
  N=$(printf '%s' "$NORM" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
  PAGES+="${NORM}"$'\n'
  if [ "$N" -lt "$PAGE_LIMIT" ]; then break; fi
  CURSOR=$(last_cursor "$NORM")
  if [ "$PAGE" -ge 200 ]; then
    cv_warn "limite de 200 páginas atingido — parando a paginação"
    break
  fi
done

# Filtra estritamente channel == "api" e deduplica (defesa em profundidade).
TARGETS=$(printf '%s' "$PAGES" | python3 -c '
import json, sys
items = []
for line in sys.stdin:
    line = line.strip()
    if line:
        items.extend(json.loads(line))
seen = set()
for c in items:
    if c.get("channel") != "api":
        continue
    cid = c.get("id")
    if not cid or cid in seen:
        continue
    seen.add(cid)
    created = (c.get("createdAt") or "")[:16].replace("T", " ")
    print(cid + "\t" + created)
')

TOTAL=$(printf '%s' "$TARGETS" | grep -c . || true)

if [ "$TOTAL" -eq 0 ]; then
  cv_info "Nenhuma conversa de teste (canal api) encontrada."
  if [ "$CV_JSON" = "1" ]; then
    printf '{"scanned":0,"deleted":0,"failed":[]}\n'
  fi
  exit 0
fi

cv_info ""
cv_info "Conversas de teste encontradas (canal api): ${TOTAL}"
printf '%s\n' "$TARGETS" | while IFS=$'\t' read -r cid created; do
  [ -n "$cid" ] && cv_info "  - ${cid}  (${created})"
done
cv_info ""

# Dupla confirmação manual (pulada por CV_YES=1 / --yes).
cv_confirm "Confirma a limpeza das ${TOTAL} conversa(s) de teste listadas acima?"
cv_confirm "Última confirmação: deletar DEFINITIVAMENTE ${TOTAL} conversa(s) do canal api?"

DELETED=0
FAILED=0
FAILED_IDS=""

while IFS=$'\t' read -r cid created; do
  [ -n "$cid" ] || continue
  if OUT=$( cv_request DELETE "/conversation/${cid}" && printf '%s' "$CV_RESP" ); then
    OK=$(printf '%s' "$OUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("1" if isinstance(d, dict) and d.get("success") else "0")
except Exception:
    print("0")
')
    if [ "$OK" = "1" ]; then
      DELETED=$((DELETED + 1))
      cv_info "  ✅ ${cid}"
    else
      FAILED=$((FAILED + 1))
      FAILED_IDS+="${cid} "
      cv_warn "  ❌ ${cid}: $(cv_err_msg "$OUT")"
    fi
  else
    FAILED=$((FAILED + 1))
    FAILED_IDS+="${cid} "
    cv_warn "  ❌ ${cid}: falha no DELETE"
  fi
  sleep "${CV_DELETE_PACE:-1}"
done <<< "$TARGETS"

cv_info ""
if [ "$CV_JSON" = "1" ]; then
  python3 - "$TOTAL" "$DELETED" "$FAILED" "$FAILED_IDS" <<'PY'
import json, sys
scanned = int(sys.argv[1]); deleted = int(sys.argv[2]); failed = int(sys.argv[3])
failed_ids = [x for x in sys.argv[4].split() if x]
print(json.dumps({"scanned": scanned, "deleted": deleted, "failed": failed_ids}, ensure_ascii=False))
PY
else
  echo "Resumo: ${DELETED} deletada(s) de ${TOTAL} encontrada(s); ${FAILED} falha(s)."
  [ "$FAILED" -gt 0 ] && echo "Falhas: ${FAILED_IDS}"
fi

[ "$FAILED" -eq 0 ]
