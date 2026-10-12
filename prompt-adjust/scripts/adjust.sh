#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — fluxo guiado de ajuste de um agente:
# config atual -> teste baseline -> escolher mudança (prompt/modelo/temperatura)
# -> aplicar -> retestar -> relatório antes/depois.
#
# Uso: ./adjust.sh <api-key> <agent-id> <query> [opções]
#
# Ver SOURCES.md na raiz do repositório. Nada é gravado em /tmp (só mktemp -d
# transitório, removido no fim).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: adjust.sh <api-key> <agent-id> <query> [opções]

Fluxo guiado de ajuste:
  1) mostra a configuração atual do agente;
  2) roda a query de teste (baseline);
  3) pergunta o que mudar: system prompt, modelo ou temperatura;
  4) mostra antes/depois (com diff quando for prompt) e pede confirmação;
  5) aplica o PATCH;
  6) retesta a MESMA query e mostra o comparativo antes/depois.

Argumentos:
  <api-key>    API key do Chatvolt (ou exporte CHATVOLT_API_KEY)
  <agent-id>   ID do agente
  <query>      Pergunta usada no baseline e no reteste

Opções (sem elas, a escolha é interativa):
  --change <prompt|model|temperature>  O que mudar
  --file <path>        Novo system prompt (com --change prompt)
  --text <text>        Novo system prompt (com --change prompt)
  --stdin              Novo system prompt pela entrada padrão (com --change prompt)
  --value <v>          Novo modelo (--change model) ou temperatura (--change temperature)
  --no-retest          Não reenvia a query depois de aplicar a mudança
  -h, --help           Esta ajuda

Confirmação:
  Toda aplicação pede confirmação; pule com CV_YES=1.
  Sem TTY e sem --change, o script explica o que passar e sai (não trava).

Saída:
  Relatório em stdout; andamento/diff em stderr.
  Com CV_JSON=1 imprime SOMENTE o JSON final do relatório em stdout.

Exit codes:
  0 ok (inclusive "nada a mudar") · 1 erro de cliente · 3 quota (402) · 4 rede
  · 5 servidor · 130 cancelado

Exemplos:
  adjust.sh "$CHATVOLT_API_KEY" <agent-id> 'Qual o prazo de entrega?'
  adjust.sh "$CHATVOLT_API_KEY" <agent-id> 'Olá' --change temperature --value 0.2
  adjust.sh "$CHATVOLT_API_KEY" <agent-id> 'Olá' --change prompt --file novo.txt
EOF
}

CHANGE=''
VALUE=''
SRC=''
SRC_VALUE=''
RETEST=1
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --change) shift; CHANGE="${1:-}"; [ -n "$CHANGE" ] || cv_die "--change exige um valor"; shift ;;
    --change=*) CHANGE="${1#--change=}"; shift ;;
    --value) shift; VALUE="${1:-}"; [ -n "$VALUE" ] || cv_die "--value exige um valor"; shift ;;
    --value=*) VALUE="${1#--value=}"; shift ;;
    --file) shift; SRC=file; SRC_VALUE="${1:-}"; [ -n "$SRC_VALUE" ] || cv_die "--file exige um caminho"; shift ;;
    --file=*) SRC=file; SRC_VALUE="${1#--file=}"; shift ;;
    --text) shift; SRC=text; SRC_VALUE="${1:-}"; [ -n "$SRC_VALUE" ] || cv_die "--text exige um valor"; shift ;;
    --text=*) SRC=text; SRC_VALUE="${1#--text=}"; shift ;;
    --stdin) SRC=stdin; shift ;;
    --no-retest) RETEST=0; shift ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) cv_die "opção desconhecida: $1 (use --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
AGENT_ID="${POS[1]:-}"
QUERY="${POS[2]:-}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id: adjust.sh <api-key> <agent-id> <query>"
[ -n "$QUERY" ] || cv_die "informe a query: adjust.sh <api-key> <agent-id> <query>"

case "$CHANGE" in
  ''|prompt|model|temperature) : ;;
  *) cv_die "--change inválido: '${CHANGE}' — use prompt, model ou temperature" ;;
esac

step() { printf '\n== %s ==\n' "$1" >&2; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

fetch_agent() {
  cv_get "/agents/${AGENT_ID}"
  cv_unwrap "$CV_RESP" > "$1"
}

run_query() {
  local body
  body=$(python3 - "$QUERY" <<'PY'
import json, sys
print(json.dumps({"query": sys.argv[1], "streaming": False}))
PY
)
  cv_request POST "/agents/${AGENT_ID}/query" "$body"
  printf '%s' "$CV_RESP" > "$1"
}

short_answer() {
  python3 - "$1" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    raw = json.load(fh)
d = raw
if isinstance(raw, dict) and "answer" not in raw and isinstance(raw.get("data"), dict):
    d = raw["data"]
if not isinstance(d, dict):
    print("(resposta inesperada)")
    raise SystemExit
answer = d.get("answer")
text = str(answer) if answer is not None else "(sem resposta)"
lines = [ln for ln in text.strip().splitlines() if ln.strip()][:12]
print("\n".join(lines) if lines else "(resposta vazia)")
PY
}

conv_id() {
  python3 - "$1" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    raw = json.load(fh)
d = raw
if isinstance(raw, dict) and "conversationId" not in raw and isinstance(raw.get("data"), dict):
    d = raw["data"]
print(d.get("conversationId") or "" if isinstance(d, dict) else "")
PY
}

# ── 1. Configuração atual ───────────────────────────────────────────────────
step "1/6 Configuração atual"
fetch_agent "$TMPD/antes.json"
IFS=$'\t' read -r CUR_NAME CUR_MODEL CUR_TEMP CUR_PROMPT_LEN CUR_TOOLS < <(python3 - "$TMPD/antes.json" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
tools = a.get("tools") if isinstance(a.get("tools"), list) else []
print(
    str(a.get("name") or "-").replace("\t", " ")
    + "\t" + str(a.get("modelName") or "-")
    + "\t" + ("-" if a.get("temperature") is None else str(a.get("temperature")))
    + "\t" + str(len(a.get("systemPrompt") or ""))
    + "\t" + str(len(tools))
)
PY
)

echo "Agente:       ${AGENT_ID} (${CUR_NAME})" >&2
echo "Modelo:       ${CUR_MODEL}" >&2
echo "Temperatura:  ${CUR_TEMP}" >&2
echo "System prompt: ${CUR_PROMPT_LEN} caracteres" >&2
echo "Tools:        ${CUR_TOOLS}" >&2

# ── 2. Baseline ─────────────────────────────────────────────────────────────
step "2/6 Teste baseline"
echo "Query: ${QUERY}" >&2
run_query "$TMPD/baseline.json"
BASE_CONV=$(conv_id "$TMPD/baseline.json")
echo "Conversa baseline: ${BASE_CONV:-nenhuma}" >&2
echo "--- resposta baseline (início) ---" >&2
short_answer "$TMPD/baseline.json" >&2
echo "--- fim ---" >&2

# ── 3. Escolha da mudança ───────────────────────────────────────────────────
step "3/6 O que mudar"
if [ -z "$CHANGE" ]; then
  if [ ! -t 0 ]; then
    cv_die "sem TTY para o menu interativo. Informe --change prompt|model|temperature
  (prompt: --file <path>|--text <text>|--stdin · model: --value <modelo> · temperature: --value <0.0-1.0>)"
  fi
  echo "  1) system prompt" >&2
  echo "  2) modelo" >&2
  echo "  3) temperatura" >&2
  echo "  0) nada (apenas mostrar o baseline)" >&2
  printf 'Escolha: ' >&2
  read -r choice
  case "$choice" in
    1) CHANGE=prompt ;;
    2) CHANGE=model ;;
    3) CHANGE=temperature ;;
    0|'') CHANGE=none ;;
    *) cv_die "escolha inválida: '${choice}'" ;;
  esac
fi

if [ "$CHANGE" = "none" ]; then
  RESULT=$(python3 - "$AGENT_ID" "$CUR_NAME" "$CUR_MODEL" "$CUR_TEMP" "$CUR_PROMPT_LEN" "$BASE_CONV" <<'PY'
import json, sys
print(json.dumps({
    "agentId": sys.argv[1], "name": sys.argv[2], "changed": False,
    "before": {"model": sys.argv[3], "temperature": sys.argv[4], "promptLength": int(sys.argv[5])},
    "after": None, "baselineConversationId": sys.argv[6] or None, "retestConversationId": None,
}, ensure_ascii=False))
PY
)
  echo "" >&2
  cv_emit "$RESULT" '
import json, sys
d = json.load(sys.stdin)
print("Nenhuma mudança escolhida — apenas o baseline foi executado.")
print("Conversa criada (apague depois com conversation-cleanup): " + str(d.get("baselineConversationId") or "-"))
'
  exit 0
fi

case "$CHANGE" in
  prompt)
    [ -n "$SRC" ] || {
      if [ -t 0 ]; then
        printf 'Caminho do arquivo com o novo system prompt (vazio cancela): ' >&2
        read -r SRC_VALUE
        [ -n "$SRC_VALUE" ] || { echo "Cancelado." >&2; exit 130; }
        SRC=file
      else
        cv_die "--change prompt exige --file <path>, --text <text> ou --stdin"
      fi
    }
    case "$SRC" in
      file)
        [ -f "$SRC_VALUE" ] || cv_die "arquivo não encontrado: ${SRC_VALUE}"
        cp -- "$SRC_VALUE" "$TMPD/depois.txt"
        ;;
      text) printf '%s' "$SRC_VALUE" > "$TMPD/depois.txt" ;;
      stdin) cat > "$TMPD/depois.txt" ;;
    esac
    NEW_PROMPT_LEN=$(python3 -c 'import sys; sys.stdout.write(str(len(open(sys.argv[1], encoding="utf-8", errors="replace").read())))' "$TMPD/depois.txt")
    [ "$NEW_PROMPT_LEN" -gt 0 ] || cv_die "o novo system prompt está vazio"
    ;;
  model)
    if [ -z "$VALUE" ]; then
      [ -t 0 ] || cv_die "--change model exige --value <modelo> (veja list-models.sh)"
      printf 'Novo modelo (ex.: gpt_41): ' >&2
      read -r VALUE
      [ -n "$VALUE" ] || { echo "Cancelado." >&2; exit 130; }
    fi
    ;;
  temperature)
    if [ -z "$VALUE" ]; then
      [ -t 0 ] || cv_die "--change temperature exige --value <0.0-1.0>"
      printf 'Nova temperatura (0.0-1.0): ' >&2
      read -r VALUE
      [ -n "$VALUE" ] || { echo "Cancelado." >&2; exit 130; }
    fi
    python3 - "$VALUE" <<'PY' || cv_die "temperatura inválida: '${VALUE}' — use um número entre 0.0 e 1.0"
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    sys.stderr.write("valor não numérico\n")
    raise SystemExit(1)
if value < 0.0 or value > 1.0:
    sys.stderr.write("valor fora da faixa 0.0-1.0\n")
    raise SystemExit(1)
PY
    ;;
esac

# ── 4. Antes/depois + confirmação ───────────────────────────────────────────
step "4/6 Diferenças e confirmação"
BODY=''
case "$CHANGE" in
  prompt)
    echo "System prompt: ${CUR_PROMPT_LEN} -> ${NEW_PROMPT_LEN} caracteres" >&2
    python3 - "$TMPD/antes.json" "$TMPD/antes.txt" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write(a.get("systemPrompt") or "")
PY
    if cmp -s "$TMPD/antes.txt" "$TMPD/depois.txt"; then
      cv_warn "o prompt enviado é idêntico ao atual"
    fi
    echo "--- diff (antes -> depois) ---" >&2
    python3 - "$TMPD/antes.txt" "$TMPD/depois.txt" <<'PY' >&2
import difflib, sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    antes = fh.read().splitlines()
with open(sys.argv[2], encoding="utf-8", errors="replace") as fh:
    depois = fh.read().splitlines()

diff = list(difflib.unified_diff(antes, depois, fromfile="antes", tofile="depois", lineterm="", n=3))
if not diff:
    print("(sem diferenças)")
else:
    limite = 300
    for linha in diff[:limite]:
        print(linha)
    if len(diff) > limite:
        print("... (" + str(len(diff) - limite) + " linhas de diff omitidas)")
PY
    echo "--- fim do diff ---" >&2
    BODY=$(python3 - "$TMPD/depois.txt" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    print(json.dumps({"systemPrompt": fh.read()}))
PY
)
    CONFIRM_MSG="Aplicar o novo system prompt (${CUR_PROMPT_LEN} -> ${NEW_PROMPT_LEN} caracteres) no agente ${AGENT_ID}?"
    ;;
  model)
    cv_get "/agents/models"
    cv_unwrap "$CV_RESP" > "$TMPD/models.json"
    VALID=$(python3 - "$TMPD/models.json" "$VALUE" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    raw = json.load(fh)
models = raw.get("models") if isinstance(raw, dict) else raw
if not isinstance(models, list):
    models = []
print("1" if any(isinstance(m, dict) and m.get("model_name") == sys.argv[2] for m in models) else "0")
PY
)
    if [ "$VALID" != "1" ]; then
      SUG=$(python3 - "$TMPD/models.json" "$VALUE" <<'PY'
import difflib, json, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    raw = json.load(fh)
models = raw.get("models") if isinstance(raw, dict) else raw
names = [str(m.get("model_name")) for m in models if isinstance(m, dict) and m.get("model_name")] if isinstance(models, list) else []
sug = difflib.get_close_matches(sys.argv[2], names, n=5, cutoff=0.3)
if not sug:
    prefix = sys.argv[2].lower()[:3]
    sug = [n for n in names if prefix and n.lower().startswith(prefix)][:5]
if not sug:
    sug = names[:5]
print(", ".join(sug) if sug else "(lista de modelos vazia)")
PY
)
      cv_die "modelo desconhecido: '${VALUE}'. Sugestões próximas: ${SUG}
Consulte a lista oficial com: list-models.sh <api-key> [--filter <regex>]"
    fi
    echo "Modelo: ${CUR_MODEL} -> ${VALUE}" >&2
    BODY=$(python3 - "$VALUE" <<'PY'
import json, sys
print(json.dumps({"modelName": sys.argv[1]}))
PY
)
    CONFIRM_MSG="Trocar o modelo de '${CUR_MODEL}' para '${VALUE}' no agente ${AGENT_ID}?"
    ;;
  temperature)
    echo "Temperatura: ${CUR_TEMP} -> ${VALUE}" >&2
    BODY=$(python3 - "$VALUE" <<'PY'
import json, sys
print(json.dumps({"temperature": float(sys.argv[1])}))
PY
)
    CONFIRM_MSG="Trocar a temperatura de ${CUR_TEMP} para ${VALUE} no agente ${AGENT_ID}?"
    ;;
esac

cv_confirm "$CONFIRM_MSG"

# ── 5. Aplicar ──────────────────────────────────────────────────────────────
step "5/6 Aplicando PATCH /agents/${AGENT_ID}"
cv_request PATCH "/agents/${AGENT_ID}" "$BODY"
printf '%s' "$CV_RESP" > "$TMPD/depois_resp.json"

IFS=$'\t' read -r NEW_MODEL NEW_TEMP NEW_PROMPT_LEN_AFTER < <(python3 - "$TMPD/depois_resp.json" "$CUR_MODEL" "$CUR_TEMP" "${NEW_PROMPT_LEN:-$CUR_PROMPT_LEN}" <<'PY'
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        d = json.load(fh)
except Exception:
    d = {}
if isinstance(d, dict) and isinstance(d.get("data"), dict) and "error" not in d:
    d = d["data"]
if not isinstance(d, dict):
    d = {}

model = str(d.get("modelName") or sys.argv[2])
temp = d.get("temperature")
temp = sys.argv[3] if temp is None else str(temp)
prompt = d.get("systemPrompt")
prompt_len = str(len(prompt)) if isinstance(prompt, str) else sys.argv[4]
print(model + "\t" + temp + "\t" + prompt_len)
PY
)

echo "Modelo agora:      ${NEW_MODEL}" >&2
echo "Temperatura agora: ${NEW_TEMP}" >&2

# ── 6. Reteste e relatório ──────────────────────────────────────────────────
RETEST_CONV=''
if [ "$RETEST" = "1" ]; then
  step "6/6 Reteste com a mesma query"
  run_query "$TMPD/depois.json"
  RETEST_CONV=$(conv_id "$TMPD/depois.json")
  echo "Conversa do reteste: ${RETEST_CONV:-nenhuma}" >&2
  echo "--- resposta depois (início) ---" >&2
  short_answer "$TMPD/depois.json" >&2
  echo "--- fim ---" >&2
else
  step "6/6 Reteste (pulado por --no-retest)"
fi

RESULT=$(python3 - "$TMPD" "$AGENT_ID" "$CUR_NAME" "$CUR_MODEL" "$CUR_TEMP" "$CUR_PROMPT_LEN" \
                 "$NEW_MODEL" "$NEW_TEMP" "$NEW_PROMPT_LEN_AFTER" "$CHANGE" "$BASE_CONV" "$RETEST_CONV" "$RETEST" <<'PY'
import json, os, sys

tmpd, agent_id = sys.argv[1], sys.argv[2]
before = {"model": sys.argv[4], "temperature": sys.argv[5], "promptLength": int(sys.argv[6])}
after = {"model": sys.argv[7], "temperature": sys.argv[8], "promptLength": int(sys.argv[9])}

def load(name):
    path = os.path.join(tmpd, name)
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            raw = json.load(fh)
    except Exception:
        return None
    d = raw
    if isinstance(raw, dict) and "answer" not in raw and isinstance(raw.get("data"), dict):
        d = raw["data"]
    if not isinstance(d, dict):
        return None
    return {"answer": d.get("answer"), "conversationId": d.get("conversationId")}

out = {
    "agentId": agent_id,
    "name": sys.argv[3],
    "change": sys.argv[10],
    "changed": True,
    "before": before,
    "after": after,
    "baselineConversationId": sys.argv[11] or None,
    "retestConversationId": (sys.argv[12] or None) if sys.argv[13] == "1" else None,
    "baseline": load("baseline.json"),
    "retest": load("depois.json") if sys.argv[13] == "1" else None,
}
print(json.dumps(out, ensure_ascii=False))
PY
)

cv_emit "$RESULT" '
import json, sys

d = json.load(sys.stdin)
before, after = d.get("before") or {}, d.get("after") or {}
print("=" * 66)
print("  Relatório do ajuste — agente " + str(d.get("agentId")) + " (" + str(d.get("name")) + ")")
print("=" * 66)
print("Mudança aplicada: " + str(d.get("change")))
print("Modelo:        " + str(before.get("model")) + " -> " + str(after.get("model")))
print("Temperatura:   " + str(before.get("temperature")) + " -> " + str(after.get("temperature")))
print("Prompt:        " + str(before.get("promptLength")) + " -> " + str(after.get("promptLength")) + " caracteres")

base = d.get("baseline") or {}
print("")
print("Resposta baseline: " + str((base.get("answer") or "(não capturada)"))[:400])
if d.get("retest") is not None:
    retest = d.get("retest") or {}
    print("Resposta depois:   " + str((retest.get("answer") or "(resposta vazia)"))[:400])

convs = [c for c in (d.get("baselineConversationId"), d.get("retestConversationId")) if c]
print("")
if convs:
    print("Conversas de teste criadas (canal api) — apague com conversation-cleanup:")
    for c in convs:
        print("  - " + str(c))
else:
    print("Nenhuma conversa de teste criada.")
print("")
print("Próximos passos: valide outras perguntas com test-query.sh e confira o prompt com get-agent.sh.")
'
