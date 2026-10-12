#!/usr/bin/env bash
# steps.sh — CRUD das etapas (steps) de um cenário do CRM (Chatvolt).
#
# Rotas (openapi "CRM Steps"):
#   GET    /crm/step?scenarioId=…[&agentId=…]   lista -> ARRAY na raiz
#   POST   /crm/step                            cria (scenarioId + name no CORPO;
#                                               a API exige também trigger OU prompt)
#   PUT    /crm/step                            atualiza (id + name no CORPO)
#   DELETE /crm/step                            apaga (id no CORPO, sem path param)
#
# Medido ao vivo (2026-10-12): GET /crm/step SEM scenarioId responde HTTP 500
# {"error":"scenario ID is required"} — por isso o scenarioId é validado aqui.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: steps.sh <api-key> <subcomando> [opções]

Subcomandos:
  list   <scenario-id> [--agent <agent-id>]      lista as etapas do cenário
  show   <step-id> --scenario <scenario-id>      mostra uma etapa (obrigatório)
  create <scenario-id> --name "<nome>" (--trigger "<t>" | --prompt "<p>") [opções]
  update <step-id> --name "<nome>" [opções]      (a API exige `name` no corpo)
  delete <step-id> [--scenario <scenario-id>] [--yes]

Opções de create/update:
  --name <nome>                  nome da etapa (obrigatório)
  --trigger <texto>              gatilho/palavra-chave da etapa
  --prompt <texto>               prompt principal da etapa
  --initial-message <texto>      mensagem inicial enviada ao ativar a etapa
  --agent <agent-id>             agente associado à etapa (agentId)
  --default-status <s>           RESOLVED | UNRESOLVED | HUMAN_REQUESTED
  --default-priority <p>         LOW | MEDIUM | HIGH
  --assignee-logic <modo>        none | clear | single_user | random_selected |
                                 fair_distribution_selected
  --auto-next-step <step-id>     etapa para transição automática
  --auto-next-time <segundos>    espera antes da transição automática
  --auto-next-unit <m|h|d>       unidade de --auto-next-time
  --required | --not-required    etapa obrigatória (isRequired)
  --json '<objeto>'              campos extras da etapa (ex.: zapi, whatsapp,
                                 requestContact, defaultTags, webhookUrl)
  --yes                          pula a confirmação (delete; = CV_YES=1)
  -h, --help                     mostra esta ajuda

Exemplos:
  steps.sh "$CHATVOLT_API_KEY" list cmpwwpn1r04hl12pfoglarith
  steps.sh "$CHATVOLT_API_KEY" create "$SC" --name "Qualificação" --prompt "Pergunte o segmento"
  steps.sh "$CHATVOLT_API_KEY" update cmpwwqm4304hu12pforj5jobz --name "Qualificação v2"
  steps.sh "$CHATVOLT_API_KEY" delete cmpwwqm4304hu12pforj5jobz --scenario "$SC"
  CV_YES=1 steps.sh "$CHATVOLT_API_KEY" delete cmpwwqm4304hu12pforj5jobz

Contrato: POST responde 201 com a etapa; PUT/DELETE devolvem a etapa afetada.
Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

# cv_check_json_object <json> — valida que --json é um objeto JSON (helper local).
cv_check_json_object() {
  [ -n "$1" ] || return 0
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception as e:
    sys.stderr.write("ERRO: --json inválido: %s\n" % e)
    raise SystemExit(1)
if not isinstance(d, dict):
    sys.stderr.write('ERRO: --json deve ser um OBJETO JSON (ex.: {"requestContact":{"phone":true}})\n')
    raise SystemExit(1)
PY
}

# cv_validate_step <corpo-json> <create|update> — valida o corpo antes de enviar.
cv_validate_step() {
  python3 - "$1" "$2" <<'PY' >&2
import json, sys
p = json.loads(sys.argv[1])
mode = sys.argv[2]
err = []
if mode == "create" and not p.get("scenarioId"):
    err.append("scenarioId obrigatório")
if not p.get("name"):
    err.append("name obrigatório (a API exige no corpo de POST e PUT)")
if mode == "create" and not p.get("trigger") and not p.get("prompt"):
    err.append("informe --trigger e/ou --prompt (a API exige ao menos um dos dois no POST)")
enums = {
    "defaultStatus": ["RESOLVED", "UNRESOLVED", "HUMAN_REQUESTED"],
    "defaultPriority": ["LOW", "MEDIUM", "HIGH"],
    "autoNextTimeUnit": ["m", "h", "d"],
    "assigneeLogicType": ["none", "clear", "single_user", "random_selected", "fair_distribution_selected"],
}
for key, allowed in enums.items():
    v = p.get(key)
    if v is not None and v not in allowed:
        err.append("%s=%r inválido (use: %s)" % (key, v, ", ".join(allowed)))
if mode == "create" and p.get("trigger") and p.get("prompt"):
    print("AVISO: trigger e prompt no mesmo corpo — o contrato declara oneOf (a API pode responder 400)")
if err:
    for e in err:
        print("ERRO: %s" % e)
    raise SystemExit(1)
PY
}

[ $# -ge 1 ] || { usage >&2; exit 1; }

POS=()
AGENT=""
NAME=""
NAME_SET=0
SCENARIO_FLAG=""
KV=()
EXTRA=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent)
      [ -n "${2:-}" ] || { usage >&2; cv_die "--agent exige o id do agente"; }
      AGENT="$2"; KV+=(agentId "$2"); shift 2 ;;
    --name)
      [ -n "${2:-}" ] || { usage >&2; cv_die "--name exige o nome da etapa"; }
      NAME="$2"; NAME_SET=1; shift 2 ;;
    --trigger|--prompt|--initial-message|--default-status|--default-priority|--assignee-logic|--auto-next-step|--auto-next-time|--auto-next-unit)
      case "$1" in
        --trigger)          KEY=trigger ;;
        --prompt)           KEY=prompt ;;
        --initial-message)  KEY=initialMessage ;;
        --default-status)   KEY=defaultStatus ;;
        --default-priority) KEY=defaultPriority ;;
        --assignee-logic)   KEY=assigneeLogicType ;;
        --auto-next-step)   KEY=autoNextStepId ;;
        --auto-next-time)   KEY=autoNextTime ;;
        --auto-next-unit)   KEY=autoNextTimeUnit ;;
      esac
      [ $# -ge 2 ] || { usage >&2; cv_die "$1 exige um valor"; }
      VAL="$2"
      case "$KEY" in
        autoNextTime) case "$VAL" in ''|*[!0-9]*) cv_die "--auto-next-time exige um inteiro em segundos";; esac ;;
      esac
      KV+=("$KEY" "$VAL"); shift 2 ;;
    --required)     KV+=(isRequired true); shift ;;
    --not-required) KV+=(isRequired false); shift ;;
    --scenario)
      [ -n "${2:-}" ] || { usage >&2; cv_die "--scenario exige o id do cenário"; }
      SCENARIO_FLAG="$2"; shift 2 ;;
    --json)
      [ -n "${2:-}" ] || { usage >&2; cv_die "--json exige um objeto JSON"; }
      EXTRA="$2"; shift 2 ;;
    --yes) CV_YES=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *)  POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
CMD="${POS[1]:-}"
ARG="${POS[2]:-}"
cv_check_json_object "$EXTRA"

LIST_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else (d.get("data") or [])
if not items:
    print("Nenhuma etapa nesta listagem.")
else:
    print(f"{len(items)} etapa(s):")
    for s in items:
        req = "obrigatória" if s.get("isRequired") else "opcional"
        print(f"  [{s.get('index')}] {s.get('id')}  {s.get('name')}  ({req})")
        print(f"      gatilho: {s.get('trigger') or '(vazio)'}")
        print(f"      prompt:  {(s.get('prompt') or '(vazio)')[:120]}")
        if s.get("initialMessage"):
            print(f"      msg inicial: {s['initialMessage']}")
        if s.get("autoNextStepId"):
            print(f"      auto-next: {s['autoNextStepId']} em {s.get('autoNextTime')} {s.get('autoNextTimeUnit')}")
        if s.get("defaultStatus") or s.get("defaultPriority"):
            print(f"      padrões: status={s.get('defaultStatus')} prioridade={s.get('defaultPriority')}")
PY
)

DETAIL_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
print(f"Etapa {d.get('name')} ({d.get('id')}) — índice {d.get('index')}")
print(f"  gatilho:     {d.get('trigger') or '(vazio)'}")
print(f"  prompt:      {d.get('prompt') or '(vazio)'}")
print(f"  msg inicial: {d.get('initialMessage') or '(nenhuma)'}")
print(f"  obrigatória: {d.get('isRequired')}")
print(f"  auto-next:   {d.get('autoNextStepId') or '(nenhuma)'} / {d.get('autoNextTime')} {d.get('autoNextTimeUnit')}")
print(f"  padrões:     status={d.get('defaultStatus')} prioridade={d.get('defaultPriority')} atribuição={d.get('assigneeLogicType')}")
PY
)

# cv_report <verbo> — imprime o resultado de POST/PUT/DELETE (CV_RESP global).
cv_report() {
  if [ "$CV_JSON" = "1" ]; then
    printf '%s\n' "$CV_RESP"
  else
    python3 - "$CV_RESP" "$1" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
verb = sys.argv[2]
if isinstance(d, dict) and d.get("id"):
    print(f"✅ Etapa {verb}: {d.get('name')} ({d['id']}) — índice {d.get('index')}")
else:
    print(f"✅ Etapa {verb} — resposta da API:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
PY
  fi
}

# cv_find_step <scenario-id> <step-id> — imprime a etapa (JSON) buscada na lista.
cv_find_step() {
  cv_get "/crm/step?scenarioId=${1}${AGENT:+&agentId=${AGENT}}"
  printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else (d.get("data") or [])
s = next((x for x in items if x.get("id") == sys.argv[1]), None)
print(json.dumps(s, ensure_ascii=False) if s else "")
' "$2"
}

case "$CMD" in
  list)
    [ -n "$ARG" ] || { usage >&2; cv_die "list exige <scenario-id> (GET /crm/step sem scenarioId responde 500)"; }
    cv_get "/crm/step?scenarioId=${ARG}${AGENT:+&agentId=${AGENT}}"
    cv_emit "$CV_RESP" "$LIST_FORMAT"
    ;;

  show)
    [ -n "$ARG" ] || { usage >&2; cv_die "show exige <step-id>"; }
    [ -n "$SCENARIO_FLAG" ] || { usage >&2; cv_die "show exige --scenario <scenario-id> (não existe GET /crm/step/{id})"; }
    FOUND=$(cv_find_step "$SCENARIO_FLAG" "$ARG")
    [ -n "$FOUND" ] || cv_die "etapa ${ARG} não encontrada no cenário ${SCENARIO_FLAG}"
    cv_emit "$FOUND" "$DETAIL_FORMAT"
    ;;

  create)
    [ -n "$ARG" ] || { usage >&2; cv_die "create exige <scenario-id>"; }
    BODY=$(python3 - "$ARG" "$NAME" "$EXTRA" "${KV[@]+"${KV[@]}"}" <<'PY'
import json, sys
scenario_id, name, extra = sys.argv[1:4]
p = {"scenarioId": scenario_id, "name": name}
kv = sys.argv[4:]
for i in range(0, len(kv), 2):
    p[kv[i]] = kv[i + 1]
if extra:
    p.update(json.loads(extra))
print(json.dumps(p, ensure_ascii=False))
PY
)
    cv_validate_step "$BODY" create
    cv_request POST "/crm/step" "$BODY"
    cv_report "criada"
    ;;

  update)
    [ -n "$ARG" ] || { usage >&2; cv_die "update exige <step-id>"; }
    if [ "$NAME_SET" = 0 ] && [ -n "$SCENARIO_FLAG" ]; then
      # PUT exige `name` no corpo: reaproveita o nome atual (leitura antes da escrita).
      FOUND=$(cv_find_step "$SCENARIO_FLAG" "$ARG")
      [ -n "$FOUND" ] || cv_die "etapa ${ARG} não encontrada no cenário ${SCENARIO_FLAG} para reaproveitar o nome"
      NAME=$(printf '%s' "$FOUND" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name") or "")')
      cv_warn "--name omitido: reaproveitando o nome atual da etapa (\"${NAME}\") — PUT exige name no corpo"
    fi
    BODY=$(python3 - "$ARG" "$NAME" "$EXTRA" "${KV[@]+"${KV[@]}"}" <<'PY'
import json, sys
step_id, name, extra = sys.argv[1:4]
p = {"id": step_id, "name": name}
kv = sys.argv[4:]
for i in range(0, len(kv), 2):
    p[kv[i]] = kv[i + 1]
if extra:
    p.update(json.loads(extra))
print(json.dumps(p, ensure_ascii=False))
PY
)
    cv_validate_step "$BODY" update
    cv_info "PUT /crm/step (id ${ARG}) — corpo: ${BODY}"
    cv_confirm "Aplicar as alterações na etapa ${ARG}?"
    cv_request PUT "/crm/step" "$BODY"
    cv_report "atualizada"
    ;;

  delete)
    [ -n "$ARG" ] || { usage >&2; cv_die "delete exige <step-id>"; }
    if [ -n "$SCENARIO_FLAG" ]; then
      FOUND=$(cv_find_step "$SCENARIO_FLAG" "$ARG")
      python3 - "$FOUND" "$ARG" "$SCENARIO_FLAG" <<'PY' >&2
import json, sys
raw, sid = sys.argv[1], sys.argv[2]
print("=== Etapa a apagar ===")
if raw:
    s = json.loads(raw)
    print("  id:    %s" % s.get("id"))
    print("  nome:  %s" % s.get("name"))
    print("  índice: %s" % s.get("index"))
    print("  gatilho: %s" % (s.get("trigger") or "(vazio)"))
else:
    print("AVISO: a etapa %s não apareceu na listagem do cenário %s; prosseguindo." % (sid, sys.argv[3] if len(sys.argv) > 3 else ""))
print()
print("AVISO: as conversas na etapa podem ser movidas/desvinculadas. Não há como desfazer.")
PY
    else
      cv_warn "sem --scenario não é possível inspecionar a etapa antes (GET /crm/step exige scenarioId); prosseguindo com o id informado"
    fi
    cv_confirm "Apagar a etapa ${ARG}?"
    BODY=$(python3 - "$ARG" <<'PY'
import json, sys
print(json.dumps({"id": sys.argv[1]}))
PY
)
    # `Connection: close`: o DELETE carrega o id no CORPO (ver scenarios.sh).
    cv_request DELETE "/crm/step" "$BODY" -H 'Connection: close'
    cv_report "apagada"
    ;;

  "") usage >&2; cv_die "informe o subcomando (list|show|create|update|delete)" ;;
  *)  usage >&2; cv_die "subcomando desconhecido: $CMD" ;;
esac
