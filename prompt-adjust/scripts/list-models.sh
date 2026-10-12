#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — lista os modelos de LLM aceitos em modelName
#
# Uso: ./list-models.sh <api-key> [--filter <regex>] [--tools-only] [--vision-only]
#
# Contrato HTTP: GET /agents/models (endpoint PÚBLICO: array na raiz).
# Esta lista MUDA com o tempo — nunca fixe modelos em texto/documentação:
# rode este script. Ver SOURCES.md na raiz do repositório.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: list-models.sh <api-key> [opções]

Lista a tabela REAL de modelos aceitos em modelName (GET /agents/models).
Use o valor da coluna MODEL_NAME direto em update-model.sh ou no
POST /agents/{id}/query.

Argumentos:
  <api-key>      API key do Chatvolt (ou exporte CHATVOLT_API_KEY).
                 O endpoint é público, mas a key é exigida por consistência
                 com os demais scripts.

Opções:
  --filter <regex>  Filtra por regex (case-insensitive) em model_name e
                    model_description. Ex: --filter '^gpt' , --filter 'claude'
  --tools-only      Somente modelos com tool-calling (isToolCallingSupported)
  --vision-only     Somente modelos com visão (hasVision)
  -h, --help        Esta ajuda.

Saída:
  Tabela em stdout: MODEL_NAME, VISÃO, TOOLS, DESCRIÇÃO + totalizadores.
  Com CV_JSON=1 imprime SOMENTE o JSON cru do endpoint em stdout.

Exit codes:
  0 ok · 1 erro de cliente (regex inválida, nenhum resultado) · 3 quota
  · 4 rede · 5 servidor

Exemplos:
  list-models.sh "$CHATVOLT_API_KEY" --filter 'claude'
  list-models.sh "$CHATVOLT_API_KEY" --tools-only --vision-only
  CV_JSON=1 list-models.sh "$CHATVOLT_API_KEY" | jq -r '.[].model_name'
EOF
}

FILTER=''
TOOLS_ONLY=0
VISION_ONLY=0
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --filter) shift; FILTER="${1:-}"; [ -n "$FILTER" ] || cv_die "--filter exige um valor"; shift ;;
    --filter=*) FILTER="${1#--filter=}"; shift ;;
    --tools-only) TOOLS_ONLY=1; shift ;;
    --vision-only) VISION_ONLY=1; shift ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) cv_die "opção desconhecida: $1 (use --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")

if [ -n "$FILTER" ]; then
  python3 - "$FILTER" 2>/dev/null <<'PY' || cv_die "regex inválida em --filter: ${FILTER}"
import re, sys
re.compile(sys.argv[1], re.IGNORECASE)
PY
fi

cv_info "Consultando GET /agents/models ..." >&2
cv_get "/agents/models"
MODELS_JSON=$(cv_unwrap "$CV_RESP")

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$MODELS_JSON"
  exit 0
fi

CV_FILTER="$FILTER" CV_TOOLS_ONLY="$TOOLS_ONLY" CV_VISION_ONLY="$VISION_ONLY" \
cv_emit "$MODELS_JSON" '
import json, os, re, sys

raw = json.load(sys.stdin)
models = raw.get("models") if isinstance(raw, dict) else raw
if not isinstance(models, list):
    print("Resposta inesperada de GET /agents/models:")
    print(json.dumps(raw, ensure_ascii=False, indent=2))
    raise SystemExit(5)

filt = os.environ.get("CV_FILTER") or ""
tools_only = os.environ.get("CV_TOOLS_ONLY") == "1"
vision_only = os.environ.get("CV_VISION_ONLY") == "1"

rx = re.compile(filt, re.IGNORECASE) if filt else None
rows = []
for m in models:
    if not isinstance(m, dict):
        continue
    name = str(m.get("model_name") or "")
    desc = str(m.get("model_description") or "")
    if rx and not (rx.search(name) or rx.search(desc)):
        continue
    if tools_only and not m.get("isToolCallingSupported"):
        continue
    if vision_only and not m.get("hasVision"):
        continue
    rows.append(m)

if not rows:
    print("Nenhum modelo corresponde aos filtros informados.")
    raise SystemExit(1)

width = max([len("MODEL_NAME")] + [len(str(m.get("model_name") or "")) for m in rows])
print("MODEL_NAME".ljust(width) + "  " + "VISÃO".ljust(5) + "  " + "TOOLS".ljust(5) + "  DESCRIÇÃO")
print("-" * (width + 44))
for m in rows:
    name = str(m.get("model_name") or "")
    desc = str(m.get("model_description") or "")
    vision = "sim" if m.get("hasVision") else "não"
    tools = "sim" if m.get("isToolCallingSupported") else "não"
    print(name.ljust(width) + "  " + vision.ljust(5) + "  " + tools.ljust(5) + "  " + desc)

total = len(rows)
n_vision = sum(1 for m in rows if m.get("hasVision"))
n_tools = sum(1 for m in rows if m.get("isToolCallingSupported"))
print("")
print(str(total) + " modelo(s) listado(s)  ·  " + str(n_vision) + " com visão  ·  " + str(n_tools) + " com tool-calling")
if not (rx or tools_only or vision_only):
    print("Passe o MODEL_NAME desejado para update-model.sh <api-key> <agent-id> <modelo>.")
'
