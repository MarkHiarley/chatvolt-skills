#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Listar disparos (dispatches / campanhas em massa) da organização.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./list-dispatches.sh <api-key> [--search TEXTO] [--status STATUS] [--agent ID]
      [--crm-scenario ID] [--crm-step ID] [--start-date DATA] [--end-date DATA]
      [--archived] [--limit N] [--offset N] [--all]

Lista os disparos (campanhas em massa) da organização.
  GET /dispatches?offset=&limit=&search=&status=&agentId=&crmScenarioId=
                   &crmStepId=&startDate=&endDate=&archived=
  Resposta: {dispatches:[...], count, totalCount?, sentCount?, errorCount?, latestErrorMessage?}

Opções:
  --search TEXTO    busca pelo nome do disparo
  --status STATUS   filtra por status (ex.: DRAFT, SCHEDULED, QUEUED, SENDING, COMPLETED)
  --agent ID        filtra pelo agente (agentId)
  --crm-scenario ID filtra pelo cenário de CRM (crmScenarioId)
  --crm-step ID     filtra pela etapa de CRM (crmStepId)
  --start-date DATA agendados a partir desta data (ISO 8601)
  --end-date DATA   agendados até esta data (ISO 8601)
  --archived        restringe aos arquivados (archived=true); por padrão não envia o filtro
  --limit N         itens por página (padrão 100)
  --offset N        deslocamento inicial (padrão 0)
  --all             pagina automaticamente até o fim
  -h, --help        mostra esta ajuda

Exemplos:
  ./list-dispatches.sh "$CHATVOLT_API_KEY" --limit 10
  ./list-dispatches.sh "$CHATVOLT_API_KEY" --status COMPLETED --all
  CV_JSON=1 ./list-dispatches.sh "$CHATVOLT_API_KEY" --search campanha

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

LIMIT=100
OFFSET=0
ALL=0
ARCHIVED=0
SEARCH=""; STATUS=""; AGENT=""; SCEN=""; STEP=""; START=""; END=""
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --search) [ "$#" -ge 2 ] || { echo "ERRO: --search exige um valor" >&2; exit 1; }; SEARCH="$2"; shift 2 ;;
    --status) [ "$#" -ge 2 ] || { echo "ERRO: --status exige um valor" >&2; exit 1; }; STATUS="$2"; shift 2 ;;
    --agent) [ "$#" -ge 2 ] || { echo "ERRO: --agent exige um valor" >&2; exit 1; }; AGENT="$2"; shift 2 ;;
    --crm-scenario) [ "$#" -ge 2 ] || { echo "ERRO: --crm-scenario exige um valor" >&2; exit 1; }; SCEN="$2"; shift 2 ;;
    --crm-step) [ "$#" -ge 2 ] || { echo "ERRO: --crm-step exige um valor" >&2; exit 1; }; STEP="$2"; shift 2 ;;
    --start-date) [ "$#" -ge 2 ] || { echo "ERRO: --start-date exige um valor" >&2; exit 1; }; START="$2"; shift 2 ;;
    --end-date) [ "$#" -ge 2 ] || { echo "ERRO: --end-date exige um valor" >&2; exit 1; }; END="$2"; shift 2 ;;
    --archived) ARCHIVED=1; shift ;;
    --limit) [ "$#" -ge 2 ] || { echo "ERRO: --limit exige um valor" >&2; exit 1; }; LIMIT="$2"; shift 2 ;;
    --offset) [ "$#" -ge 2 ] || { echo "ERRO: --offset exige um valor" >&2; exit 1; }; OFFSET="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um número inteiro" ;; esac
case "$OFFSET" in ''|*[!0-9]*) cv_die "--offset deve ser um número inteiro" ;; esac
[ "$LIMIT" -gt 0 ] || cv_die "--limit deve ser maior que zero"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

PAGE=0
CUR="$OFFSET"
while :; do
  Q=$(python3 - "$CUR" "$LIMIT" "$SEARCH" "$STATUS" "$AGENT" "$SCEN" "$STEP" "$START" "$END" "$ARCHIVED" <<'PY'
import sys, urllib.parse
offset, limit, search, status, agent, scen, step, start, end, archived = sys.argv[1:11]
p = {"offset": offset, "limit": limit}
if search:   p["search"] = search
if status:   p["status"] = status
if agent:    p["agentId"] = agent
if scen:     p["crmScenarioId"] = scen
if step:     p["crmStepId"] = step
if start:    p["startDate"] = start
if end:      p["endDate"] = end
if archived == "1": p["archived"] = "true"
print(urllib.parse.urlencode(p))
PY
)
  cv_get "/dispatches?${Q}"
  printf '%s' "$CV_RESP" > "${TMPD}/${PAGE}.json"
  N=$(python3 - "${TMPD}/${PAGE}.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
items = d.get("dispatches") if isinstance(d, dict) else (d if isinstance(d, list) else [])
print(len(items or []))
PY
)
  [ "$ALL" = "1" ] || break
  [ "$N" -gt 0 ] || break
  [ "$N" -lt "$LIMIT" ] && break
  PAGE=$((PAGE + 1))
  CUR=$((CUR + N))
done

if [ "$CV_JSON" = "1" ]; then
  python3 - "$TMPD" <<'PY'
import glob, json, os, sys

files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items, count = [], 0
for f in files:
    d = json.load(open(f, encoding="utf-8"))
    if isinstance(d, dict):
        items.extend(d.get("dispatches") or [])
        count = int(d.get("count") or count)
    elif isinstance(d, list):
        items.extend(d)
print(json.dumps({"dispatches": items, "count": count or len(items)}, ensure_ascii=False))
PY
else
  python3 - "$TMPD" <<'PY'
import glob, json, os, sys

files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items = []
for f in files:
    d = json.load(open(f, encoding="utf-8"))
    if isinstance(d, dict):
        items.extend(d.get("dispatches") or [])
    elif isinstance(d, list):
        items.extend(d)

def cut(v, n):
    s = "" if v is None else str(v)
    return s if len(s) <= n else s[:n - 1] + "…"

if not items:
    print("Nenhum disparo encontrado.")
    raise SystemExit

print(f"{'ID':<26} {'NOME':<30} {'STATUS':<12} {'AGENTE':<26} {'AGENDADO':<21} {'ENVIADOS':>9} ERROS")
print("-" * 140)
for d in items:
    enviados = f"{d.get('sentCount', '?')}/{d.get('totalCount', '?')}"
    print(f"{cut(d.get('id'), 25):<26} {cut(d.get('name'), 29):<30} {cut(d.get('status'), 11):<12} "
          f"{cut(d.get('agentId'), 25):<26} {cut(d.get('scheduledAt'), 20):<21} {enviados:>9} "
          f"{d.get('errorCount', '?')}")
print()
print(f"{len(items)} disparo(s).")
erros = [d for d in items if d.get("latestErrorMessage")]
if erros:
    print()
    print("Última mensagem de erro por disparo:")
    for d in erros:
        print(f"  {d.get('id')}: {cut(d.get('latestErrorMessage'), 120)}")
PY
fi
