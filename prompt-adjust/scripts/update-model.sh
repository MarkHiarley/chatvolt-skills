#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — troca o modelo (modelName) de um agente (PATCH /agents/{id})
#
# Uso: ./update-model.sh <api-key> <agent-id> <model> [--force]
#
# O modelo é validado contra GET /agents/models (a lista muda com o tempo).
# Ver SOURCES.md na raiz do repositório.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: update-model.sh <api-key> <agent-id> <model> [opções]

Troca o modelo do agente. O nome é validado contra GET /agents/models (a lista
oficial, que muda com o tempo — rode list-models.sh para vê-la). Se o nome não
existir, são listadas 5 sugestões próximas e o script sai com código 1.

Argumentos:
  <api-key>    API key do Chatvolt (ou exporte CHATVOLT_API_KEY)
  <agent-id>   ID do agente
  <model>      model_name exato (ex.: gpt_41, claude_sonnet, gemini_flash)

Opções:
  --force      Reaplica mesmo se o agente já usar esse modelo
  -h, --help   Esta ajuda

Saída:
  Antes/depois em stdout; diagnósticos em stderr.
  Com CV_JSON=1 imprime SOMENTE JSON em stdout:
  {"agentId","before","after","afterDescription","updatedAt"}

Exit codes:
  0 ok · 1 erro de cliente (modelo desconhecido) · 3 quota (402) · 4 rede
  · 5 servidor · 130 cancelado

Exemplos:
  list-models.sh "$CHATVOLT_API_KEY" --filter 'claude'
  update-model.sh "$CHATVOLT_API_KEY" <agent-id> claude_sonnet
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
MODEL="${POS[2]:-}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id: update-model.sh <api-key> <agent-id> <model>"
[ -n "$MODEL" ] || cv_die "informe o modelo: update-model.sh <api-key> <agent-id> <model> (veja list-models.sh)"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

cv_info "Validando o modelo '${MODEL}' em GET /agents/models ..." >&2
cv_get "/agents/models"
cv_unwrap "$CV_RESP" > "$TMPD/models.json"

VALID=$(python3 - "$TMPD/models.json" "$MODEL" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    raw = json.load(fh)
models = raw.get("models") if isinstance(raw, dict) else raw
target = sys.argv[2]
if not isinstance(models, list):
    print("0")
    raise SystemExit
print("1" if any(isinstance(m, dict) and m.get("model_name") == target for m in models) else "0")
PY
)

if [ "$VALID" != "1" ]; then
  SUG=$(python3 - "$TMPD/models.json" "$MODEL" <<'PY'
import difflib, json, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    raw = json.load(fh)
models = raw.get("models") if isinstance(raw, dict) else raw
if not isinstance(models, list):
    models = []
names = [str(m.get("model_name")) for m in models if isinstance(m, dict) and m.get("model_name")]
target = sys.argv[2]
sug = difflib.get_close_matches(target, names, n=5, cutoff=0.3)
if not sug:
    prefix = target.lower()[:3]
    sug = [n for n in names if prefix and n.lower().startswith(prefix)][:5]
if not sug:
    sug = names[:5]
print(", ".join(sug) if sug else "(lista de modelos vazia)")
PY
)
  cv_die "modelo desconhecido: '${MODEL}'. Sugestões próximas: ${SUG}
Consulte a lista oficial com: list-models.sh <api-key> [--filter <regex>]"
fi

NEW_DESC=$(python3 - "$TMPD/models.json" "$MODEL" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    raw = json.load(fh)
models = raw.get("models") if isinstance(raw, dict) else raw
for m in models if isinstance(models, list) else []:
    if isinstance(m, dict) and m.get("model_name") == sys.argv[2]:
        print(m.get("model_description") or "")
        break
PY
)

cv_get "/agents/${AGENT_ID}"
cv_unwrap "$CV_RESP" > "$TMPD/agente.json"

CURRENT_MODEL=$(python3 - "$TMPD/agente.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
print(a.get("modelName") or "-")
PY
)

AGENT_NAME=$(python3 - "$TMPD/agente.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
print(a.get("name") or "-")
PY
)

echo "Agente: ${AGENT_ID} (${AGENT_NAME})" >&2
echo "Modelo: ${CURRENT_MODEL} -> ${MODEL}${NEW_DESC:+ (${NEW_DESC})}" >&2

if [ "$CURRENT_MODEL" = "$MODEL" ] && [ "$FORCE" != "1" ]; then
  cv_warn "o agente já usa o modelo '${MODEL}' — nada a fazer (use --force para reaplicar)"
  RESULT=$(python3 - "$AGENT_ID" "$CURRENT_MODEL" "$MODEL" "$NEW_DESC" <<'PY'
import json, sys
print(json.dumps({
    "agentId": sys.argv[1], "before": sys.argv[2], "after": sys.argv[3],
    "afterDescription": sys.argv[4] or None, "updatedAt": None, "changed": False,
}, ensure_ascii=False))
PY
)
  cv_emit "$RESULT" '
import json, sys
d = json.load(sys.stdin)
print("ℹ️  Nenhuma alteração: o modelo já é " + str(d.get("after")))
'
  exit 0
fi

cv_confirm "Trocar o modelo de '${CURRENT_MODEL}' para '${MODEL}' no agente ${AGENT_ID}?"

BODY=$(python3 - "$MODEL" <<'PY'
import json, sys
print(json.dumps({"modelName": sys.argv[1]}))
PY
)

cv_request PATCH "/agents/${AGENT_ID}" "$BODY"
printf '%s' "$CV_RESP" > "$TMPD/resposta.json"

RESULT=$(python3 - "$TMPD/resposta.json" "$AGENT_ID" "$CURRENT_MODEL" "$MODEL" "$NEW_DESC" <<'PY'
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        d = json.load(fh)
except Exception:
    d = {}
if isinstance(d, dict) and isinstance(d.get("data"), dict) and "error" not in d:
    d = d["data"]
out = {
    "agentId": sys.argv[2],
    "before": sys.argv[3],
    "after": d.get("modelName") or sys.argv[4],
    "afterDescription": sys.argv[5] or None,
    "updatedAt": d.get("updatedAt") or None,
    "changed": True,
}
print(json.dumps(out, ensure_ascii=False))
PY
)

cv_emit "$RESULT" '
import json, sys

d = json.load(sys.stdin)
print("✅ modelo atualizado")
print("   Antes:  " + str(d.get("before")))
print("   Depois: " + str(d.get("after")) + (" (" + str(d.get("afterDescription")) + ")" if d.get("afterDescription") else ""))
if d.get("updatedAt"):
    print("   Atualizado: " + str(d.get("updatedAt")))
print("   Dica: envie uma query de teste (test-query.sh) para conferir a qualidade.")
'
