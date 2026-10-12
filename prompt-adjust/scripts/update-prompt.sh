#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — atualiza o system prompt de um agente (PATCH /agents/{id})
#
# Uso: ./update-prompt.sh <api-key> <agent-id> (--file <path>|--text <text>|--stdin)
#
# Mostra o tamanho atual, o diff (difflib) e pede confirmação ANTES do PATCH.
# Ver SOURCES.md na raiz do repositório.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: update-prompt.sh <api-key> <agent-id> (--file <path>|--text <text>|--stdin) [opções]

Substitui o systemPrompt do agente. Antes de aplicar, mostra:
  1) o tamanho do prompt atual;
  2) o diff linha a linha (difflib.unified_diff);
  3) pede confirmação (pule com CV_YES=1).
Depois do PATCH imprime o tamanho novo.

Argumentos:
  <api-key>    API key do Chatvolt (ou exporte CHATVOLT_API_KEY)
  <agent-id>   ID do agente

Origem do novo prompt (exatamente uma):
  --file <path>   Lê o prompt de um arquivo (conteúdo preservado byte a byte)
  --text <text>   Usa o texto literal passado na linha de comando
  --stdin         Lê o prompt da entrada padrão (ex.: <<'PROMPT' ... PROMPT)

Opções:
  --no-diff       Não imprime o diff (útil para prompts muito grandes)
  -h, --help      Esta ajuda

Saída:
  Diagnóstico (tamanho/diff) em stderr; resultado em stdout.
  Com CV_JSON=1 imprime SOMENTE JSON em stdout:
  {"agentId","beforeLength","afterLength","updatedAt"}

Exit codes:
  0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado

Exemplos:
  update-prompt.sh "$CHATVOLT_API_KEY" <agent-id> --file novo-prompt.txt
  update-prompt.sh "$CHATVOLT_API_KEY" <agent-id> --text 'Você é um atendente...'
  update-prompt.sh "$CHATVOLT_API_KEY" <agent-id> --stdin < novo-prompt.txt
EOF
}

SRC=''
SRC_VALUE=''
SHOW_DIFF=1
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --file) shift; SRC=file; SRC_VALUE="${1:-}"; [ -n "$SRC_VALUE" ] || cv_die "--file exige um caminho"; shift ;;
    --file=*) SRC=file; SRC_VALUE="${1#--file=}"; shift ;;
    --text) shift; SRC=text; SRC_VALUE="${1:-}"; [ -n "$SRC_VALUE" ] || cv_die "--text exige um valor"; shift ;;
    --text=*) SRC=text; SRC_VALUE="${1#--text=}"; shift ;;
    --stdin) SRC=stdin; shift ;;
    --no-diff) SHOW_DIFF=0; shift ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) cv_die "opção desconhecida: $1 (use --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
AGENT_ID="${POS[1]:-}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id: update-prompt.sh <api-key> <agent-id> (--file|--text|--stdin)"
[ -n "$SRC" ] || cv_die "informe a origem do novo prompt: --file <path>, --text <text> ou --stdin (use --help)"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

case "$SRC" in
  file)
    [ -f "$SRC_VALUE" ] || cv_die "arquivo não encontrado: ${SRC_VALUE}"
    cp -- "$SRC_VALUE" "$TMPD/depois.txt"
    cv_info "Novo prompt lido de ${SRC_VALUE}" >&2
    ;;
  text)
    printf '%s' "$SRC_VALUE" > "$TMPD/depois.txt"
    cv_info "Novo prompt recebido via --text" >&2
    ;;
  stdin)
    cat > "$TMPD/depois.txt"
    cv_info "Novo prompt lido da entrada padrão" >&2
    ;;
esac

NEW_LEN=$(python3 -c 'import sys; sys.stdout.write(str(len(open(sys.argv[1], encoding="utf-8", errors="replace").read())))' "$TMPD/depois.txt")
[ "$NEW_LEN" -gt 0 ] || cv_die "o novo prompt está vazio — PATCH cancelado"

cv_get "/agents/${AGENT_ID}"
cv_unwrap "$CV_RESP" > "$TMPD/agente.json"

AGENT_NAME=$(python3 - "$TMPD/agente.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
print(a.get("name") or "-")
PY
)

python3 - "$TMPD/agente.json" "$TMPD/antes.txt" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    a = json.load(fh)
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write(a.get("systemPrompt") or "")
PY

OLD_LEN=$(python3 -c 'import sys; sys.stdout.write(str(len(open(sys.argv[1], encoding="utf-8", errors="replace").read())))' "$TMPD/antes.txt")

echo "Agente:            ${AGENT_ID} (${AGENT_NAME})" >&2
echo "Prompt atual:      ${OLD_LEN} caracteres" >&2
echo "Prompt novo:       ${NEW_LEN} caracteres" >&2
if [ "$OLD_LEN" = "$NEW_LEN" ] && cmp -s "$TMPD/antes.txt" "$TMPD/depois.txt"; then
  cv_warn "o prompt enviado é idêntico ao atual"
fi

if [ "$SHOW_DIFF" = "1" ]; then
  echo "--- diff (antes -> depois; linhas com - saem, + entram) ---" >&2
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
fi

cv_confirm "Aplicar o novo system prompt (${OLD_LEN} -> ${NEW_LEN} caracteres) no agente ${AGENT_ID}?"

BODY=$(python3 - "$TMPD/depois.txt" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    print(json.dumps({"systemPrompt": fh.read()}))
PY
)

cv_request PATCH "/agents/${AGENT_ID}" "$BODY"
printf '%s' "$CV_RESP" > "$TMPD/resposta.json"

RESULT=$(python3 - "$TMPD/resposta.json" "$AGENT_ID" "$OLD_LEN" "$NEW_LEN" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    resp = fh.read()
agent_id, old_len, new_len = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
try:
    d = json.loads(resp)
except Exception:
    d = {}
if isinstance(d, dict) and isinstance(d.get("data"), dict) and "error" not in d:
    d = d["data"]
after = d.get("systemPrompt")
out = {
    "agentId": agent_id,
    "name": d.get("name") or None,
    "beforeLength": old_len,
    "afterLength": len(after) if isinstance(after, str) else new_len,
    "updatedAt": d.get("updatedAt") or None,
}
print(json.dumps(out, ensure_ascii=False))
PY
)

cv_emit "$RESULT" '
import json, sys

d = json.load(sys.stdin)
print("✅ system prompt atualizado")
print("   Agente:      " + str(d.get("agentId")))
print("   Tamanho:     " + str(d.get("beforeLength")) + " -> " + str(d.get("afterLength")) + " caracteres")
if d.get("updatedAt"):
    print("   Atualizado:  " + str(d.get("updatedAt")))
print("   Dica: teste com test-query.sh antes de encerrar a sessão.")
'
