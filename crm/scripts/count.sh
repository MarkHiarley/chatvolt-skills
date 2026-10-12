#!/usr/bin/env bash
# count.sh — conta as conversas de um cenário do CRM (Chatvolt).
#
# Rota: GET /crm/conversation/count?scenarioId=…[&stepId=…]
#
# Medido ao vivo (2026-10-12):
#   * resposta real é {"total": N} na raiz (a doc sugere {data:{…},success});
#   * sem scenarioId -> HTTP 400 {"error":"scenarioId is required"};
#   * cenário inexistente -> HTTP 404 {"error":"Scenario not found"};
#   * o parâmetro stepId é ACEITO mas IGNORADO: o total é sempre o do cenário
#     inteiro (verificado com dois steps do mesmo cenário e um id inexistente,
#     todos devolvendo o mesmo total). Para contagem POR ETAPA use
#     `step-conversations.sh count <cenário> --step <etapa>` (rota
#     /crm/scenario/{id}/conversation?isCount=true&stepId=…).
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: count.sh <api-key> <scenario-id> [--step <step-id>]

Conta as conversas vinculadas ao cenário (GET /crm/conversation/count).

Argumentos:
  <api-key>        Chave de API (ou exporte CHATVOLT_API_KEY)
  <scenario-id>    ID do cenário do CRM (obrigatório — a rota exige scenarioId)

Opções:
  --step <step-id> passo apenas informativo: a rota aceita stepId mas IGNORA
                   (o total devolvido é o do cenário inteiro). Para a contagem
                   por etapa, use step-conversations.sh count <cenário> --step
  -h, --help       mostra esta ajuda

Exemplos:
  count.sh "$CHATVOLT_API_KEY" cmpwwpn1r04hl12pfoglarith
  CV_JSON=1 count.sh "$CHATVOLT_API_KEY" cmpwwpn1r04hl12pfoglarith

Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage >&2; exit 1; }

POS=()
STEP=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --step) [ -n "${2:-}" ] || { usage >&2; cv_die "--step exige o id da etapa"; }
            STEP="$2"; shift 2 ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *)  POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
SCENARIO_ID="${POS[1]:-}"
[ -n "$SCENARIO_ID" ] || { usage >&2; cv_die "informe o <scenario-id> (GET /crm/conversation/count exige scenarioId)"; }

Q="/crm/conversation/count?scenarioId=${SCENARIO_ID}"
if [ -n "$STEP" ]; then
  Q="${Q}&stepId=${STEP}"
  cv_warn "--step é ignorado por esta rota (medido ao vivo): o total é o do cenário. Para contagem por etapa use step-conversations.sh count"
fi

cv_get "$Q"

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$CV_RESP"
else
  python3 - "$CV_RESP" "$SCENARIO_ID" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
total = d.get("total")
if total is None and isinstance(d.get("data"), dict):
    total = d["data"].get("total")
if total is None:
    print("Resposta da API sem o campo total:")
    print(json.dumps(d, indent=2, ensure_ascii=False))
else:
    print(f"{total} conversa(s) no cenário {sys.argv[2]}.")
PY
fi
