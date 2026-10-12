#!/usr/bin/env bash
# conversation-logs.sh — CRUD dos logs de conversa do CRM (Chatvolt).
#
# Rotas (openapi "CRM Conversation Logs"):
#   GET    /crm/conversationLog                lista paginada {data, pagination}
#   POST   /crm/conversationLog                cria (conversationId, scenarioId,
#                                              stepId, status)
#   GET    /crm/conversationLog/{logId}        objeto do log
#   PUT    /crm/conversationLog/{logId}        atualiza o status (corpo: status)
#   PATCH  /crm/conversationLog/{logId}        idêntico ao PUT (só `status` muda)
#   DELETE /crm/conversationLog/{logId}        apaga -> {"message": …}
#
# Medido ao vivo (2026-10-12): GET /crm/conversationLog?limit=2 devolve
# {"data":[…],"pagination":{"page":1,"limit":2,"total":190,"totalPages":95}}.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: conversation-logs.sh <api-key> <subcomando> [opções]

Subcomandos:
  list   [--conversation <id>] [--scenario <id>] [--step <id>] [--status <s>]
         [--page <n>] [--limit <n>]
  get    <log-id>
  create --conversation <id> --scenario <id> --step <id> [--status <s>]
  update <log-id> --status <s>            (PUT)
  patch  <log-id> --status <s>            (PATCH — idêntico ao PUT na API)
  delete <log-id> [--yes]

Opções:
  --conversation <id>  filtra/define a conversa (conversationId)
  --scenario <id>      filtra/define o cenário (scenarioId)
  --step <id>          filtra/define a etapa (stepId)
  --status <s>         inactive | active | error (padrão no create: active)
  --page <n>           página (mínimo 1, padrão 1)
  --limit <n>          itens por página (1-100, padrão 10)
  --yes                pula a confirmação (delete; = CV_YES=1)
  -h, --help           mostra esta ajuda

Exemplos:
  conversation-logs.sh "$CHATVOLT_API_KEY" list --scenario "$SC" --limit 5
  conversation-logs.sh "$CHATVOLT_API_KEY" get cmu1p13r20ak98a6bqv61gwua
  conversation-logs.sh "$CHATVOLT_API_KEY" create --conversation "$CONV" --scenario "$SC" --step "$ST"
  conversation-logs.sh "$CHATVOLT_API_KEY" update cmu1p13r20ak98a6bqv61gwua --status inactive
  CV_YES=1 conversation-logs.sh "$CHATVOLT_API_KEY" delete cmu1p13r20ak98a6bqv61gwua

Contrato: a listagem vem em {"data":[…],"pagination":{…}}; create devolve o log
criado. Só o `status` é atualizável (PUT e PATCH são equivalentes).
Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage >&2; exit 1; }

POS=()
CONV=""
SCENARIO=""
STEP=""
STATUS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --conversation) [ -n "${2:-}" ] || { usage >&2; cv_die "--conversation exige o id"; }
                    CONV="$2"; shift 2 ;;
    --scenario)     [ -n "${2:-}" ] || { usage >&2; cv_die "--scenario exige o id"; }
                    SCENARIO="$2"; shift 2 ;;
    --step)         [ -n "${2:-}" ] || { usage >&2; cv_die "--step exige o id"; }
                    STEP="$2"; shift 2 ;;
    --status)       [ -n "${2:-}" ] || { usage >&2; cv_die "--status exige o valor"; }
                    STATUS="$2"; shift 2 ;;
    --page)         [ -n "${2:-}" ] || { usage >&2; cv_die "--page exige um inteiro >= 1"; }
                    case "$2" in ''|*[!0-9]*) cv_die "--page exige um inteiro >= 1";; esac
                    [ "$2" -ge 1 ] || cv_die "--page exige um inteiro >= 1"
                    PAGE="$2"; shift 2 ;;
    --limit)        [ -n "${2:-}" ] || { usage >&2; cv_die "--limit exige um inteiro entre 1 e 100"; }
                    case "$2" in ''|*[!0-9]*) cv_die "--limit exige um inteiro entre 1 e 100";; esac
                    [ "$2" -ge 1 ] && [ "$2" -le 100 ] || cv_die "--limit deve estar entre 1 e 100 (máximo da API)"
                    LIMIT="$2"; shift 2 ;;
    --yes)          CV_YES=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *)  POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
CMD="${POS[1]:-}"
LOG_ID="${POS[2]:-}"

if [ -n "$STATUS" ]; then
  case "$STATUS" in
    inactive|active|error) ;;
    *) cv_die "--status inválido: ${STATUS} (use: inactive, active, error)" ;;
  esac
fi

LIST_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d:
    items, pg = d.get("data") or [], d.get("pagination") or {}
    print(f"{len(items)} de {pg.get('total')} log(s) — página {pg.get('page')}/{pg.get('totalPages')} (limite {pg.get('limit')})")
else:
    items = d if isinstance(d, list) else (d.get("data") or [])
    print(f"{len(items)} log(s)")
for it in items:
    step = it.get("step") or {}
    scen = it.get("scenario") or {}
    conv = it.get("conversation") or {}
    print(f"  - {it.get('id')}  status={it.get('status')}  criado em {it.get('createdAt')}")
    print(f"      conversa: {it.get('conversationId')} ({conv.get('title') or 'sem título'})")
    print(f"      cenário:  {scen.get('name')} ({it.get('scenarioId')})  etapa: {step.get('name')} [{step.get('index')}] ({it.get('stepId')})")
PY
)

DETAIL_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
step = d.get("step") or {}
scen = d.get("scenario") or {}
conv = d.get("conversation") or {}
print(f"Log CRM {d.get('id')} — status {d.get('status')}")
print(f"  conversa:  {d.get('conversationId')} ({conv.get('title') or 'sem título'})")
print(f"  cenário:   {scen.get('name')} ({d.get('scenarioId')})")
print(f"  etapa:     {step.get('name')} [{step.get('index')}] ({d.get('stepId')})")
print(f"  criado:    {d.get('createdAt')} · atualizado: {d.get('updatedAt')}")
print(f"  quem moveu: {d.get('whoMoved') or '(não informado)'} · usuário: {d.get('userId') or '(não informado)'}")
PY
)

cv_report() {
  if [ "$CV_JSON" = "1" ]; then
    printf '%s\n' "$CV_RESP"
  else
    python3 - "$CV_RESP" "$1" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
verb = sys.argv[2]
if isinstance(d, dict) and d.get("id"):
    print(f"✅ Log {verb}: {d['id']} — status {d.get('status')} (conversa {d.get('conversationId')}, etapa {d.get('stepId')})")
elif isinstance(d, dict) and d.get("message"):
    print(f"✅ {d['message']}")
else:
    print(f"✅ Log {verb} — resposta da API:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
PY
  fi
}

case "$CMD" in
  list)
    Q="/crm/conversationLog"
    P=()
    if [ -n "$CONV" ]; then P+=("conversationId=${CONV}"); fi
    if [ -n "$SCENARIO" ]; then P+=("scenarioId=${SCENARIO}"); fi
    if [ -n "$STEP" ]; then P+=("stepId=${STEP}"); fi
    if [ -n "$STATUS" ]; then P+=("status=${STATUS}"); fi
    if [ -n "${PAGE:-}" ]; then P+=("page=${PAGE}"); fi
    if [ -n "${LIMIT:-}" ]; then P+=("limit=${LIMIT}"); fi
    if [ "${#P[@]}" -gt 0 ]; then Q="${Q}?$(IFS='&'; echo "${P[*]}")"; fi
    cv_get "$Q"
    cv_emit "$CV_RESP" "$LIST_FORMAT"
    ;;

  get)
    [ -n "$LOG_ID" ] || { usage >&2; cv_die "get exige <log-id>"; }
    cv_get "/crm/conversationLog/${LOG_ID}"
    cv_emit "$CV_RESP" "$DETAIL_FORMAT"
    ;;

  create)
    [ -n "$CONV" ] || { usage >&2; cv_die "create exige --conversation <id>"; }
    [ -n "$SCENARIO" ] || { usage >&2; cv_die "create exige --scenario <id>"; }
    [ -n "$STEP" ] || { usage >&2; cv_die "create exige --step <id>"; }
    BODY=$(python3 - "$CONV" "$SCENARIO" "$STEP" "${STATUS:-active}" <<'PY'
import json, sys
conv, scen, step, status = sys.argv[1:5]
print(json.dumps({"conversationId": conv, "scenarioId": scen, "stepId": step, "status": status}, ensure_ascii=False))
PY
)
    cv_request POST "/crm/conversationLog" "$BODY"
    cv_report "criado"
    ;;

  update|patch)
    [ -n "$LOG_ID" ] || { usage >&2; cv_die "${CMD} exige <log-id>"; }
    [ -n "$STATUS" ] || { usage >&2; cv_die "${CMD} exige --status (inactive|active|error)"; }
    BODY=$(python3 - "$STATUS" <<'PY'
import json, sys
print(json.dumps({"status": sys.argv[1]}))
PY
)
    METHOD=PUT
    if [ "$CMD" = "patch" ]; then METHOD=PATCH; fi
    cv_info "${METHOD} /crm/conversationLog/${LOG_ID} — status → ${STATUS}"
    cv_confirm "Aplicar o novo status no log ${LOG_ID}?"
    cv_request "$METHOD" "/crm/conversationLog/${LOG_ID}" "$BODY"
    cv_report "atualizado"
    ;;

  delete)
    [ -n "$LOG_ID" ] || { usage >&2; cv_die "delete exige <log-id>"; }
    cv_get "/crm/conversationLog/${LOG_ID}"
    python3 - "$CV_RESP" <<'PY' >&2
import json, sys
d = json.loads(sys.argv[1])
print("=== Log a apagar ===")
print("  id:       %s" % d.get("id"))
print("  status:   %s" % d.get("status"))
print("  conversa: %s" % d.get("conversationId"))
print("  cenário:  %s   etapa: %s" % (d.get("scenarioId"), d.get("stepId")))
print()
print("AVISO: o registro de passagem pelo CRM será apagado. Não há como desfazer.")
PY
    cv_confirm "Apagar o log ${LOG_ID}?"
    cv_request DELETE "/crm/conversationLog/${LOG_ID}"
    cv_report "apagado"
    ;;

  "") usage >&2; cv_die "informe o subcomando (list|get|create|update|patch|delete)" ;;
  *)  usage >&2; cv_die "subcomando desconhecido: $CMD" ;;
esac
