#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — ajusta a temperatura (creatividade) de um agente (PATCH /agents/{id})
#
# Uso: ./update-temperature.sh <api-key> <agent-id> <0.0-1.0> [--force]
#
# Ver SOURCES.md na raiz do repositório.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: update-temperature.sh <api-key> <agent-id> <valor> [opções]

Ajusta a temperatura do agente (faixa válida: 0.0 a 1.0).
Referência prática: 0.0-0.2 = respostas determinísticas (fluxos, dados
sensíveis); 0.3-0.6 = equilibrado (atendimento geral); 0.7-1.0 = mais criativo.

Argumentos:
  <api-key>    API key do Chatvolt (ou exporte CHATVOLT_API_KEY)
  <agent-id>   ID do agente
  <valor>      Número entre 0.0 e 1.0 (ex.: 0.2, 0.5, 0.8)

Opções:
  --force      Reaplica mesmo se a temperatura já for essa
  -h, --help   Esta ajuda

Saída:
  Antes/depois em stdout; diagnósticos em stderr.
  Com CV_JSON=1 imprime SOMENTE JSON em stdout:
  {"agentId","before","after","updatedAt","changed"}

Exit codes:
  0 ok · 1 erro de cliente (valor fora da faixa/não numérico) · 3 quota (402)
  · 4 rede · 5 servidor · 130 cancelado

Exemplos:
  update-temperature.sh "$CHATVOLT_API_KEY" <agent-id> 0.2
  update-temperature.sh "$CHATVOLT_API_KEY" <agent-id> 0.7 --force
EOF
}

FORCE=0
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=1; shift ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) cv_die "opção desconhecida: $1 (use --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
AGENT_ID="${POS[1]:-}"
TEMP_IN="${POS[2]:-}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id: update-temperature.sh <api-key> <agent-id> <0.0-1.0>"
[ -n "$TEMP_IN" ] || cv_die "informe a temperatura: update-temperature.sh <api-key> <agent-id> <0.0-1.0>"

TEMP=$(python3 - "$TEMP_IN" <<'PY'
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    sys.stderr.write("valor não numérico\n")
    raise SystemExit(1)
if value < 0.0 or value > 1.0:
    sys.stderr.write("valor fora da faixa 0.0-1.0\n")
    raise SystemExit(1)
print(repr(value))
PY
) || cv_die "temperatura inválida: '${TEMP_IN}' — use um número entre 0.0 e 1.0"

cv_info "Temperatura nova: ${TEMP_IN} (normalizada: ${TEMP})" >&2

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

cv_get "/agents/${AGENT_ID}"
cv_unwrap "$CV_RESP" > "$TMPD/agente.json"

AGENT_NAME=$(python3 - "$TMPD/agente.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
print(str(a.get("name") or "-").replace("\t", " "))
PY
)

CURRENT_TEMP=$(python3 - "$TMPD/agente.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
temp = a.get("temperature")
print("-" if temp is None else temp)
PY
)

echo "Agente: ${AGENT_ID} (${AGENT_NAME})" >&2
echo "Temperatura: ${CURRENT_TEMP} -> ${TEMP}" >&2

SAME=$(python3 - "$CURRENT_TEMP" "$TEMP" <<'PY'
import sys
try:
    print("1" if float(sys.argv[1]) == float(sys.argv[2]) else "0")
except Exception:
    print("0")
PY
)

if [ "$SAME" = "1" ] && [ "$FORCE" != "1" ]; then
  cv_warn "o agente já usa a temperatura ${TEMP} — nada a fazer (use --force para reaplicar)"
  RESULT=$(python3 - "$AGENT_ID" "$CURRENT_TEMP" "$TEMP" <<'PY'
import json, sys
print(json.dumps({
    "agentId": sys.argv[1], "before": sys.argv[2], "after": sys.argv[3],
    "updatedAt": None, "changed": False,
}, ensure_ascii=False))
PY
)
  cv_emit "$RESULT" '
import json, sys
d = json.load(sys.stdin)
print("ℹ️  Nenhuma alteração: a temperatura já é " + str(d.get("after")))
'
  exit 0
fi

cv_confirm "Trocar a temperatura de ${CURRENT_TEMP} para ${TEMP} no agente ${AGENT_ID}?"

BODY=$(python3 - "$TEMP" <<'PY'
import json, sys
print(json.dumps({"temperature": float(sys.argv[1])}))
PY
)

cv_request PATCH "/agents/${AGENT_ID}" "$BODY"
printf '%s' "$CV_RESP" > "$TMPD/resposta.json"

RESULT=$(python3 - "$TMPD/resposta.json" "$AGENT_ID" "$CURRENT_TEMP" "$TEMP" <<'PY'
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        d = json.load(fh)
except Exception:
    d = {}
if isinstance(d, dict) and isinstance(d.get("data"), dict) and "error" not in d:
    d = d["data"]
after = d.get("temperature")
out = {
    "agentId": sys.argv[2],
    "before": sys.argv[3],
    "after": str(after) if after is not None else sys.argv[4],
    "updatedAt": d.get("updatedAt") or None,
    "changed": True,
}
print(json.dumps(out, ensure_ascii=False))
PY
)

cv_emit "$RESULT" '
import json, sys

d = json.load(sys.stdin)
print("✅ temperatura atualizada")
print("   Antes:  " + str(d.get("before")))
print("   Depois: " + str(d.get("after")))
if d.get("updatedAt"):
    print("   Atualizado: " + str(d.get("updatedAt")))
print("   Dica: compare uma mesma pergunta antes/depois com test-query.sh.")
'
