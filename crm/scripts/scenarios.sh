#!/usr/bin/env bash
# scenarios.sh — CRUD dos cenários do CRM (Chatvolt).
#
# Rotas (openapi "CRM Scenarios"):
#   GET    /crm/scenario    lista (filtro opcional agentId) -> ARRAY na raiz
#   POST   /crm/scenario    cria (name obrigatório) -> 201 com o cenário
#   PUT    /crm/scenario    atualiza (id + name obrigatórios, no CORPO)
#   DELETE /crm/scenario    apaga (id no CORPO, sem path param)
#
# Não existe GET /crm/scenario/{id}: para inspecionar um cenário o script lista
# e filtra pelo id (use --agent para reduzir a lista).
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: scenarios.sh <api-key> <subcomando> [opções]

Subcomandos:
  list   [--agent <agent-id>]                    lista os cenários do CRM
  show   <scenario-id> [--agent <agent-id>]      mostra um cenário específico
  create --name "<nome>" [--description "<txt>"] [--json '<extra>']
  update <scenario-id> --name "<nome>" [--description "<txt>"] [--json '<extra>']
  delete <scenario-id> [--yes]                   apaga (confirmação obrigatória)

Opções:
  --name <nome>         nome do cenário (obrigatório em create/update)
  --description <txt>   descrição; em update use --description "" para limpar
  --agent <agent-id>    filtra a listagem por agente (agentId)
  --json '<objeto>'     campos extras mesclados no corpo de create/update
  --yes                 pula a confirmação (equivalente a CV_YES=1)
  -h, --help            mostra esta ajuda

Exemplos:
  scenarios.sh "$CHATVOLT_API_KEY" list
  scenarios.sh "$CHATVOLT_API_KEY" list --agent "$CHATVOLT_AGENT_ID"
  scenarios.sh "$CHATVOLT_API_KEY" create --name "Funil de vendas" --description "Leads inbound"
  scenarios.sh "$CHATVOLT_API_KEY" update cmabc123 --name "Funil de vendas v2"
  CV_YES=1 scenarios.sh "$CHATVOLT_API_KEY" delete cmabc123

Contrato: GET devolve um ARRAY na raiz; POST responde 201 com o cenário criado;
PUT/DELETE devolvem o cenário afetado. delete exige confirmação (CV_YES=1 pula).
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
    sys.stderr.write('ERRO: --json deve ser um OBJETO JSON (ex.: {"description":"texto"})\n')
    raise SystemExit(1)
PY
}

[ $# -ge 1 ] || { usage >&2; exit 1; }

POS=()
AGENT=""
NAME=""
DESC=""
DESC_SET=0
EXTRA=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent)       [ -n "${2:-}" ] || { usage >&2; cv_die "--agent exige o id do agente"; }
                   AGENT="$2"; shift 2 ;;
    --name)        [ -n "${2:-}" ] || { usage >&2; cv_die "--name exige o nome do cenário"; }
                   NAME="$2"; shift 2 ;;
    --description) [ $# -ge 2 ] || { usage >&2; cv_die "--description exige o texto (use \"\" para limpar)"; }
                   DESC="$2"; DESC_SET=1; shift 2 ;;
    --json)        [ -n "${2:-}" ] || { usage >&2; cv_die "--json exige um objeto JSON"; }
                   EXTRA="$2"; shift 2 ;;
    --yes)         CV_YES=1; shift ;;
    --)            shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*)            usage >&2; cv_die "opção desconhecida: $1" ;;
    *)             POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
CMD="${POS[1]:-}"
SCENARIO_ID="${POS[2]:-}"
cv_check_json_object "$EXTRA"

Q=""
if [ -n "$AGENT" ]; then Q="?agentId=${AGENT}"; fi

LIST_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else (d.get("data") or [])
if not items:
    print("Nenhum cenário CRM encontrado.")
else:
    print(f"{len(items)} cenário(s) CRM:")
    for s in items:
        print(f"  - {s.get('id')}  {s.get('name')}")
        if (s.get("description") or "").strip():
            print(f"      {s['description']}")
        print(f"      criado em {s.get('createdAt')} · atualizado em {s.get('updatedAt')}")
PY
)

DETAIL_FORMAT=$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
items = d if isinstance(d, list) else [d]
for s in items:
    print(f"Cenário {s.get('name')} ({s.get('id')})")
    print(f"  descrição: {s.get('description') or '(sem descrição)'}")
    print(f"  criado em {s.get('createdAt')} · atualizado em {s.get('updatedAt')}")
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
    print(f"✅ Cenário {verb}: {d.get('name')} ({d['id']})")
else:
    print(f"✅ Cenário {verb} — resposta da API:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
PY
  fi
}

case "$CMD" in
  list)
    cv_get "/crm/scenario${Q}"
    cv_emit "$CV_RESP" "$LIST_FORMAT"
    ;;

  show)
    [ -n "$SCENARIO_ID" ] || { usage >&2; cv_die "show exige <scenario-id>"; }
    cv_get "/crm/scenario${Q}"
    FOUND=$(python3 - "$CV_RESP" "$SCENARIO_ID" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
items = d if isinstance(d, list) else (d.get("data") or [])
s = next((x for x in items if x.get("id") == sys.argv[2]), None)
print(json.dumps(s, ensure_ascii=False) if s else "")
PY
)
    [ -n "$FOUND" ] || cv_die "cenário ${SCENARIO_ID} não encontrado na listagem${AGENT:+ do agente ${AGENT}}"
    cv_emit "$FOUND" "$DETAIL_FORMAT"
    ;;

  create)
    [ -n "$NAME" ] || { usage >&2; cv_die "create exige --name"; }
    BODY=$(python3 - "$NAME" "$DESC_SET" "$DESC" "$EXTRA" <<'PY'
import json, sys
name, desc_set, desc, extra = sys.argv[1:5]
p = {"name": name}
if desc_set == "1":
    p["description"] = desc or None
if extra:
    p.update(json.loads(extra))
print(json.dumps(p, ensure_ascii=False))
PY
)
    cv_request POST "/crm/scenario" "$BODY"
    cv_report "criado"
    ;;

  update)
    [ -n "$SCENARIO_ID" ] || { usage >&2; cv_die "update exige <scenario-id>"; }
    [ -n "$NAME" ] || { usage >&2; cv_die "update exige --name"; }
    BODY=$(python3 - "$SCENARIO_ID" "$NAME" "$DESC_SET" "$DESC" "$EXTRA" <<'PY'
import json, sys
sid, name, desc_set, desc, extra = sys.argv[1:6]
p = {"id": sid, "name": name}
if desc_set == "1":
    p["description"] = desc or None
if extra:
    p.update(json.loads(extra))
print(json.dumps(p, ensure_ascii=False))
PY
)
    cv_info "PUT /crm/scenario (id ${SCENARIO_ID}) — corpo: ${BODY}"
    cv_confirm "Aplicar as alterações no cenário ${SCENARIO_ID}?"
    cv_request PUT "/crm/scenario" "$BODY"
    cv_report "atualizado"
    ;;

  delete)
    [ -n "$SCENARIO_ID" ] || { usage >&2; cv_die "delete exige <scenario-id>"; }
    cv_get "/crm/scenario${Q}"
    python3 - "$CV_RESP" "$SCENARIO_ID" <<'PY' >&2
import json, sys
d = json.loads(sys.argv[1])
items = d if isinstance(d, list) else (d.get("data") or [])
s = next((x for x in items if x.get("id") == sys.argv[2]), None)
print("=== Cenário a apagar ===")
if s:
    print("  id:   %s" % s.get("id"))
    print("  nome: %s" % s.get("name"))
    print("  desc: %s" % (s.get("description") or "(sem descrição)"))
else:
    print("AVISO: o cenário %s não apareceu na listagem (%s); prosseguindo."
          % (sys.argv[2], "--agent está filtrando" if len(sys.argv) > 3 else "confira o id"))
print()
print("AVISO: apagar o cenário remove as etapas e os vínculos de conversa. Não há como desfazer.")
PY
    cv_confirm "Apagar o cenário ${SCENARIO_ID}?"
    BODY=$(python3 - "$SCENARIO_ID" <<'PY'
import json, sys
print(json.dumps({"id": sys.argv[1]}))
PY
)
    # `Connection: close`: o DELETE carrega o id no CORPO; em servidores HTTP/1.1
    # simples que não leem esse corpo (stub de teste), o keep-alive tentaria
    # parsear os bytes restantes e sujaria a conexão. O header apenas encerra a
    # conexão após a resposta e é inofensivo para a API real.
    cv_request DELETE "/crm/scenario" "$BODY" -H 'Connection: close'
    cv_report "apagado"
    ;;

  "") usage >&2; cv_die "informe o subcomando (list|show|create|update|delete)" ;;
  *)  usage >&2; cv_die "subcomando desconhecido: $CMD" ;;
esac
