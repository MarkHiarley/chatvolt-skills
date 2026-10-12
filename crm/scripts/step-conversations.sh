#!/usr/bin/env bash
# step-conversations.sh — vínculo de conversas com cenário/etapa do CRM (Chatvolt).
#
# Rotas (openapi "CRM Scenarios"):
#   GET    /crm/scenario/{scenarioId}/conversation   lista (stepId, page, limit,
#                                                    isCount, showInactiveConversations)
#   DELETE /crm/scenario/{scenarioId}/conversation?conversationId=…   desvincula
#   POST   /crm/step/conversation                    adiciona conversa a uma etapa
#   POST   /crm/step/move                            move conversa para outra etapa
#
# Medido ao vivo (2026-10-12, cenário cmpwwpn1r04hl12pfoglarith):
#   GET …/conversation            -> ARRAY na raiz (cada item traz `step` e `conversation`)
#   GET …?isCount=true            -> Mapa {stepId: quantidade}
#   GET …?isCount=true&stepId=…   -> {"count": N}
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: step-conversations.sh <api-key> <subcomando> [opções]

Subcomandos:
  list   <scenario-id> [--step <step-id>] [--page <n>] [--limit <n>] [--inactive]
  count  <scenario-id> [--step <step-id>]
  add    <scenario-id> <conversation-id> (--step <step-id> | --step-index <n>)
  move   <conversation-id> (--dest-step <step-id> | --dest-step-index <n>)
         [--scenario <scenario-id>]
  remove <scenario-id> <conversation-id> [--yes]

Opções:
  --step <step-id>         etapa (filtro da listagem, ou destino de `add`)
  --step-index <n>         índice da etapa no cenário (alternativa a --step)
  --page <n>               página da listagem (a API usa 0/1 — padrão 0)
  --limit <n>              itens por página
  --inactive               inclui conversas indisponíveis (showInactiveConversations)
  --dest-step <step-id>    etapa de destino do `move`
  --dest-step-index <n>    índice da etapa de destino do `move`
  --scenario <scenario-id> cenário (contexto do `move`; obrigatório se o destino
                           for --dest-step-index)
  --yes                    pula a confirmação (remove; = CV_YES=1)
  -h, --help               mostra esta ajuda

Exemplos:
  step-conversations.sh "$CHATVOLT_API_KEY" list "$SC" --limit 5
  step-conversations.sh "$CHATVOLT_API_KEY" count "$SC" --step "$ST"
  step-conversations.sh "$CHATVOLT_API_KEY" add "$SC" "$CONV" --step "$ST"
  step-conversations.sh "$CHATVOLT_API_KEY" move "$CONV" --dest-step "$ST2" --scenario "$SC"
  CV_YES=1 step-conversations.sh "$CHATVOLT_API_KEY" remove "$SC" "$CONV"

Contrato: GET devolve array (ou mapa/`count` com --count); add/move devolvem o
vínculo criado; remove devolve {"message": …}.
Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage >&2; exit 1; }

POS=()
STEP=""
STEP_INDEX=""
PAGE=""
LIMIT=""
INACTIVE=0
DEST_STEP=""
DEST_INDEX=""
SCENARIO_FLAG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --step|--dest-step|--step-index|--dest-step-index|--page|--limit|--scenario)
      case "$1" in
        --step)            KEY=step ;;
        --dest-step)       KEY=dest ;;
        --step-index)      KEY=idx ;;
        --dest-step-index) KEY=didx ;;
        --page)            KEY=page ;;
        --limit)           KEY=limit ;;
        --scenario)        KEY=scen ;;
      esac
      [ $# -ge 2 ] || { usage >&2; cv_die "$1 exige um valor"; }
      VAL="$2"
      case "$KEY" in
        idx|didx|page|limit) case "$VAL" in ''|*[!0-9]*) cv_die "$1 exige um inteiro";; esac ;;
      esac
      case "$KEY" in
        step) STEP="$VAL" ;;
        dest) DEST_STEP="$VAL" ;;
        idx)  STEP_INDEX="$VAL" ;;
        didx) DEST_INDEX="$VAL" ;;
        page) PAGE="$VAL" ;;
        limit) LIMIT="$VAL" ;;
        scen) SCENARIO_FLAG="$VAL" ;;
      esac
      shift 2 ;;
    --inactive) INACTIVE=1; shift ;;
    --yes)      CV_YES=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *)  POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
CMD="${POS[1]:-}"
ARG1="${POS[2]:-}"
ARG2="${POS[3]:-}"

LIST_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else (d.get("data") or [])
if not items:
    print("Nenhuma conversa vinculada nesta listagem.")
else:
    print(f"{len(items)} vínculo(s) de conversa:")
    for it in items:
        step = it.get("step") or {}
        conv = it.get("conversation") or {}
        print(f"  - vínculo {it.get('id')} — conversa {it.get('conversationId')}  disponível={'sim' if it.get('available') else 'não'}  ordem={it.get('order')}")
        print(f"      cenário: {it.get('scenarioId')}  etapa: {step.get('name')} [{step.get('index')}] ({it.get('stepId')})")
        if conv:
            print(f"      canal: {conv.get('channel')}  status: {conv.get('status')}  prioridade: {conv.get('priority')}")
        print(f"      vínculo criado em {it.get('createdAt')}")
PY
)

COUNT_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "count" in d:
    print(f"{d['count']} conversa(s) nesta etapa do cenário.")
elif isinstance(d, dict):
    total = sum(v for v in d.values() if isinstance(v, int))
    print(f"{total} conversa(s) no cenário, por etapa (stepId: quantidade):")
    for k, v in d.items():
        print(f"  - {k}: {v}")
else:
    print(json.dumps(d, ensure_ascii=False))
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
if isinstance(d, dict) and d.get("message"):
    print(f"✅ {d['message']}")
elif isinstance(d, dict) and d.get("id"):
    print(f"✅ {verb}: vínculo {d.get('id')} — conversa {d.get('conversationId')} na etapa {d.get('stepId')} (cenário {d.get('scenarioId')})")
else:
    print(f"✅ {verb} — resposta da API:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
PY
  fi
}

# cv_find_link <scenario-id> <conversation-id> — imprime o vínculo (JSON) ou vazio.
cv_find_link() {
  cv_get "/crm/scenario/${1}/conversation?limit=100"
  printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else (d.get("data") or [])
it = next((x for x in items if x.get("conversationId") == sys.argv[1]), None)
print(json.dumps(it, ensure_ascii=False) if it else "")
' "$2"
}

case "$CMD" in
  list)
    [ -n "$ARG1" ] || { usage >&2; cv_die "list exige <scenario-id>"; }
    Q="/crm/scenario/${ARG1}/conversation"
    P=()
    if [ -n "$STEP" ]; then P+=("stepId=${STEP}"); fi
    if [ -n "$PAGE" ]; then P+=("page=${PAGE}"); fi
    if [ -n "$LIMIT" ]; then P+=("limit=${LIMIT}"); fi
    if [ "$INACTIVE" = 1 ]; then P+=("showInactiveConversations=true"); fi
    if [ "${#P[@]}" -gt 0 ]; then Q="${Q}?$(IFS='&'; echo "${P[*]}")"; fi
    cv_get "$Q"
    cv_emit "$CV_RESP" "$LIST_FORMAT"
    ;;

  count)
    [ -n "$ARG1" ] || { usage >&2; cv_die "count exige <scenario-id>"; }
    Q="/crm/scenario/${ARG1}/conversation?isCount=true"
    [ -n "$STEP" ] && Q="${Q}&stepId=${STEP}"
    cv_get "$Q"
    cv_emit "$CV_RESP" "$COUNT_FORMAT"
    ;;

  add)
    [ -n "$ARG1" ] || { usage >&2; cv_die "add exige <scenario-id>"; }
    [ -n "$ARG2" ] || { usage >&2; cv_die "add exige <conversation-id>"; }
    { [ -n "$STEP" ] || [ -n "$STEP_INDEX" ]; } || { usage >&2; cv_die "add exige --step <step-id> ou --step-index <n>"; }
    { [ -z "$STEP" ] || [ -z "$STEP_INDEX" ]; } || cv_die "use --step OU --step-index, não os dois"
    BODY=$(python3 - "$ARG1" "$ARG2" "$STEP" "$STEP_INDEX" <<'PY'
import json, sys
scenario_id, conversation_id, step_id, step_index = sys.argv[1:5]
p = {"scenarioId": scenario_id, "conversationId": conversation_id}
if step_id:
    p["stepId"] = step_id
else:
    p["stepIndex"] = int(step_index)
print(json.dumps(p, ensure_ascii=False))
PY
)
    cv_request POST "/crm/step/conversation" "$BODY"
    cv_report "Conversa adicionada à etapa"
    ;;

  move)
    [ -n "$ARG1" ] || { usage >&2; cv_die "move exige <conversation-id>"; }
    { [ -n "$DEST_STEP" ] || [ -n "$DEST_INDEX" ]; } || { usage >&2; cv_die "move exige --dest-step <step-id> ou --dest-step-index <n>"; }
    { [ -z "$DEST_STEP" ] || [ -z "$DEST_INDEX" ]; } || cv_die "use --dest-step OU --dest-step-index, não os dois"
    if [ -n "$DEST_INDEX" ] && [ -z "$SCENARIO_FLAG" ]; then
      cv_die "--dest-step-index exige --scenario <scenario-id> (o índice é relativo ao cenário)"
    fi
    BODY=$(python3 - "$ARG1" "$SCENARIO_FLAG" "$DEST_STEP" "$DEST_INDEX" <<'PY'
import json, sys
conversation_id, scenario_id, dest_step_id, dest_step_index = sys.argv[1:5]
p = {"conversationId": conversation_id}
if scenario_id:
    p["scenarioId"] = scenario_id
if dest_step_id:
    p["destStepId"] = dest_step_id
else:
    p["destStepIndex"] = int(dest_step_index)
print(json.dumps(p, ensure_ascii=False))
PY
)
    cv_request POST "/crm/step/move" "$BODY"
    cv_report "Conversa movida de etapa"
    ;;

  remove)
    [ -n "$ARG1" ] || { usage >&2; cv_die "remove exige <scenario-id>"; }
    [ -n "$ARG2" ] || { usage >&2; cv_die "remove exige <conversation-id>"; }
    LINK=$(cv_find_link "$ARG1" "$ARG2")
    python3 - "$LINK" "$ARG1" "$ARG2" <<'PY' >&2
import json, sys
raw, scenario_id, conv_id = sys.argv[1], sys.argv[2], sys.argv[3]
print("=== Vínculo a remover ===")
print("  cenário:      %s" % scenario_id)
print("  conversa:     %s" % conv_id)
if raw:
    it = json.loads(raw)
    step = it.get("step") or {}
    print("  etapa atual:  %s [%s] (%s)" % (step.get("name"), step.get("index"), it.get("stepId")))
    print("  disponível:   %s" % it.get("available"))
else:
    print("  AVISO: o vínculo não apareceu na 1a página (limit=100); confira os IDs.")
print()
print("AVISO: a conversa deixa o cenário (o histórico da conversa em si não é apagado).")
PY
    cv_confirm "Remover a conversa ${ARG2} do cenário ${ARG1}?"
    cv_request DELETE "/crm/scenario/${ARG1}/conversation?conversationId=${ARG2}"
    cv_report "Conversa removida do cenário"
    ;;

  "") usage >&2; cv_die "informe o subcomando (list|count|add|move|remove)" ;;
  *)  usage >&2; cv_die "subcomando desconhecido: $CMD" ;;
esac
