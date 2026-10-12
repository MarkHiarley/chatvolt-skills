#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Criar (ou atualizar) um disparo em massa.
#
# ATENÇÃO: esta é uma rota de campanha em massa. O script exige --yes explícito
# e nunca é exercitado em teste ao vivo (a suíte usa apenas o stub offline).
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./create-dispatch.sh <api-key> --name NOME --agent AGENT_ID [--id DISPATCH_ID]
      [--status STATUS] [--crm-scenario ID] [--crm-step ID] [--scheduled-at ISO]
      [--template-message TEXTO] [--interval MINUTOS] [--contact-list ID]...
      [--exclude-list ID]... [--json '<extra>'] --yes

Cria um disparo em massa (campanha) ou atualiza um existente quando --id é informado.
  POST /dispatches  ->  objeto do disparo na raiz

⚠️  AVISO: disparo em massa é uma operação de campanha.
    - A campanha nasce em `draft`; os envios acontecem quando a fila é populada
      (ver `populate-queue.sh`), que dispara mensagens REAIS para os contatos.
    - Informe --yes para confirmar que você quer criar/alterar esta campanha.
      CV_YES=1 NÃO substitui o --yes neste script.

Opções:
  --name NOME            nome da campanha (obrigatório)
  --agent ID             agente responsável (agentId, obrigatório)
  --id ID                id de um disparo existente para ATUALIZAR (upsert)
  --status STATUS        status inicial (ex.: DRAFT, SCHEDULED)
  --crm-scenario ID      cenário de CRM associado
  --crm-step ID          etapa de CRM associada
  --scheduled-at ISO     data/hora de agendamento (ISO 8601)
  --template-message T   texto/template da mensagem do disparo
  --interval MINUTOS     intervalo entre envios
  --contact-list ID      lista de contatos incluída (repetível)
  --exclude-list ID      lista de contatos excluída (repetível)
  --json '<extra>'       campos adicionais no corpo (JSON válido, mesclado por cima)
  --yes                  confirma a criação/alteração da campanha
  -h, --help             mostra esta ajuda

Exemplos:
  ./create-dispatch.sh "$CHATVOLT_API_KEY" --name "Campanha Outubro" \
      --agent "$CHATVOLT_AGENT_ID" --contact-list 30eead17-... --template-message "Olá!" --yes

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

NAME=""; AGENT=""; ID=""; STATUS=""; SCEN=""; STEP=""; SCHED=""; TEMPLATE=""; INTERVAL=""; EXTRA=""
YES=0
LISTS=(); EXCLUDES=()
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --name) [ "$#" -ge 2 ] || { echo "ERRO: --name exige um valor" >&2; exit 1; }; NAME="$2"; shift 2 ;;
    --agent) [ "$#" -ge 2 ] || { echo "ERRO: --agent exige um valor" >&2; exit 1; }; AGENT="$2"; shift 2 ;;
    --id) [ "$#" -ge 2 ] || { echo "ERRO: --id exige um valor" >&2; exit 1; }; ID="$2"; shift 2 ;;
    --status) [ "$#" -ge 2 ] || { echo "ERRO: --status exige um valor" >&2; exit 1; }; STATUS="$2"; shift 2 ;;
    --crm-scenario) [ "$#" -ge 2 ] || { echo "ERRO: --crm-scenario exige um valor" >&2; exit 1; }; SCEN="$2"; shift 2 ;;
    --crm-step) [ "$#" -ge 2 ] || { echo "ERRO: --crm-step exige um valor" >&2; exit 1; }; STEP="$2"; shift 2 ;;
    --scheduled-at) [ "$#" -ge 2 ] || { echo "ERRO: --scheduled-at exige um valor" >&2; exit 1; }; SCHED="$2"; shift 2 ;;
    --template-message) [ "$#" -ge 2 ] || { echo "ERRO: --template-message exige um valor" >&2; exit 1; }; TEMPLATE="$2"; shift 2 ;;
    --interval) [ "$#" -ge 2 ] || { echo "ERRO: --interval exige um valor" >&2; exit 1; }; INTERVAL="$2"; shift 2 ;;
    --contact-list) [ "$#" -ge 2 ] || { echo "ERRO: --contact-list exige um valor" >&2; exit 1; }; LISTS+=("$2"); shift 2 ;;
    --exclude-list) [ "$#" -ge 2 ] || { echo "ERRO: --exclude-list exige um valor" >&2; exit 1; }; EXCLUDES+=("$2"); shift 2 ;;
    --json) [ "$#" -ge 2 ] || { echo "ERRO: --json exige um valor" >&2; exit 1; }; EXTRA="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
[ -n "$NAME" ] || cv_die "--name é obrigatório"
[ -n "$AGENT" ] || cv_die "--agent é obrigatório (agentId responsável pela campanha)"
if [ -n "$INTERVAL" ]; then case "$INTERVAL" in ''|*[!0-9]*) cv_die "--interval deve ser um número inteiro (minutos)" ;; esac; fi
if [ -n "$EXTRA" ] && ! printf '%s' "$EXTRA" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  cv_die "--json não é um JSON válido"
fi
[ "$YES" = "1" ] || cv_die "--yes é obrigatório: este script cria/altera uma campanha de disparo em massa (a fila é populada depois com populate-queue.sh)"

cv_warn "POST /dispatches: criação/alteração de CAMPANHA EM MASSA."
cv_warn "A campanha nasce em 'draft'; os envios reais só começam após populate-queue.sh."
[ -z "$ID" ] || cv_warn "Atualizando o disparo existente ${ID} (upsert)."

BODY=$(python3 - "$NAME" "$AGENT" "$ID" "$STATUS" "$SCEN" "$STEP" "$SCHED" "$TEMPLATE" "$INTERVAL" "$EXTRA" "${LISTS[@]+${LISTS[@]}}" "${EXCLUDES[@]+__SEP__${EXCLUDES[@]}}" <<'PY'
import json, sys

name, agent, did, status, scen, step, sched, template, interval, extra = sys.argv[1:11]
rest = sys.argv[11:]
lists, excludes = [], []
if "__SEP__" in rest:
    i = rest.index("__SEP__")
    lists, excludes = rest[:i], rest[i + 1:]
else:
    lists = rest

body = {"name": name, "agentId": agent}
if did:      body["id"] = did
if status:   body["status"] = status
if scen:     body["crmScenarioId"] = scen
if step:     body["crmStepId"] = step
if sched:    body["scheduledAt"] = sched
if template: body["templateMessage"] = template
if interval: body["interval"] = int(interval)
if lists:    body["contactListIds"] = list(lists)
if excludes: body["exclusionContactListIds"] = list(excludes)
if extra:
    body.update(json.loads(extra))
print(json.dumps(body, ensure_ascii=False))
PY
)

cv_request POST "/dispatches" "$BODY"

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$CV_RESP"
else
  TMPF=$(mktemp)
  trap 'rm -f "$TMPF"' EXIT
  printf '%s' "$CV_RESP" > "$TMPF"
  python3 - "$TMPF" <<'PY'
import json, sys

d = json.load(open(sys.argv[1], encoding="utf-8"))
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
if not isinstance(d, dict):
    print(json.dumps(d, ensure_ascii=False, indent=2))
    raise SystemExit
print("Disparo criado/atualizado:")
for label, key in (("id", "id"), ("nome", "name"), ("status", "status"),
                   ("agente", "agentId"), ("agendado para", "scheduledAt")):
    print(f"  {label + ':':<15} {d.get(key)}")
print()
print("Próximo passo: adicione contatos à lista e rode populate-queue.sh para iniciar os envios.")
PY
fi
