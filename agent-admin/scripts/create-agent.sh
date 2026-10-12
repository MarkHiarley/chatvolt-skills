#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — create-agent
#
# Cria um agente (POST /agents). Verificado ao vivo (2026-10-12): a API exige
# `name` + `description` + `systemPrompt` no corpo (só `name` dá 400). Quando a
# organização/plano não permite novos agentes, a rota responde
# `402 {"error":"USAGE_LIMIT"}` — mensagem tratada abaixo (exit 3).
#
# Uso:
#   create-agent.sh [api-key] --name <n> --description <d> --system-prompt <p>
#                   [--model <m>] [--temperature <t>] [--visibility public|private]
#                   [--handle <slug>] [--json '<extra>'] [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1          pula a confirmação interativa
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
create-agent.sh — cria um agente no Chatvolt

Uso:
  create-agent.sh [api-key] --name <n> --description <d> --system-prompt <p>
                  [--model <m>] [--temperature <t>] [--visibility public|private]
                  [--handle <slug>] [--json '<extra>'] [--yes]

Obrigatórios (a API recusa sem os três):
  --name <n>            nome do agente
  --description <d>     descrição do agente
  --system-prompt <p>   prompt de sistema (pode vir de arquivo com @caminho)

Opcionais:
  --model <m>           modelName (veja GET /agents/models)
  --temperature <t>     temperatura 0.0-1.0
  --visibility <v>      public | private
  --handle <slug>       identificador amigável único
  --json '<extra>'      objeto JSON mesclado no corpo (tools, interfaceConfig, ...)
  --yes                 pula a confirmação
  -h, --help            mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY  API key (alternativa ao 1º argumento)
  CV_JSON=1         imprime somente JSON em stdout
  CV_YES=1          pula a confirmação interativa
  CV_API_BASE       base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

# req_soft — como cv_request, mas NÃO encerra o script: preserva CV_STATUS/CV_RESP
# e devolve o exit code, com o stderr do cv_request em REQ_ERR. Necessário para
# tratar 402 (USAGE_LIMIT) e 404 com mensagem própria.
REQ_ERR=""
req_soft() {
  local err rs rr rc
  err=$(mktemp); rs=$(mktemp); rr=$(mktemp)
  set +e
  (
    dump() { printf '%s' "${CV_STATUS:-}" >"$rs"; printf '%s' "${CV_RESP:-}" >"$rr"; }
    trap dump EXIT
    cv_request "$@"
  ) 2>"$err"
  rc=$?
  set -e
  CV_STATUS=$(cat "$rs" 2>/dev/null)
  CV_RESP=$(cat "$rr" 2>/dev/null)
  REQ_ERR=$(cat "$err" 2>/dev/null)
  rm -f "$err" "$rs" "$rr"
  return "$rc"
}

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

NAME=""
DESCRIPTION=""
SYSTEM_PROMPT=""
MODEL=""
TEMPERATURE=""
VISIBILITY=""
HANDLE=""
EXTRA=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)          [ "$#" -ge 2 ] || cv_die "--name exige um valor"; NAME="$2"; shift 2 ;;
    --description)   [ "$#" -ge 2 ] || cv_die "--description exige um valor"; DESCRIPTION="$2"; shift 2 ;;
    --system-prompt) [ "$#" -ge 2 ] || cv_die "--system-prompt exige um valor"; SYSTEM_PROMPT="$2"; shift 2 ;;
    --model)         [ "$#" -ge 2 ] || cv_die "--model exige um valor"; MODEL="$2"; shift 2 ;;
    --temperature)   [ "$#" -ge 2 ] || cv_die "--temperature exige um valor"; TEMPERATURE="$2"; shift 2 ;;
    --visibility)    [ "$#" -ge 2 ] || cv_die "--visibility exige um valor"; VISIBILITY="$2"; shift 2 ;;
    --handle)        [ "$#" -ge 2 ] || cv_die "--handle exige um valor"; HANDLE="$2"; shift 2 ;;
    --json)          [ "$#" -ge 2 ] || cv_die "--json exige um objeto JSON"; EXTRA="$2"; shift 2 ;;
    --yes)           export CV_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              cv_die "opção desconhecida: $1 (use --help)" ;;
    *)               cv_die "argumento extra: $1" ;;
  esac
done

[ -n "$NAME" ] || { usage >&2; cv_die "--name é obrigatório (a API também exige --description e --system-prompt)"; }
[ -n "$DESCRIPTION" ] || { usage >&2; cv_die "--description é obrigatório"; }
[ -n "$SYSTEM_PROMPT" ] || { usage >&2; cv_die "--system-prompt é obrigatório"; }

# @arquivo: lê o prompt de um arquivo (útil para prompts longos).
case "$SYSTEM_PROMPT" in
  @*) [ -f "${SYSTEM_PROMPT#@}" ] || cv_die "arquivo de prompt não encontrado: ${SYSTEM_PROMPT#@}"
      SYSTEM_PROMPT=$(cat "${SYSTEM_PROMPT#@}") ;;
esac

if [ -n "$VISIBILITY" ] && [ "$VISIBILITY" != "public" ] && [ "$VISIBILITY" != "private" ]; then
  cv_die "--visibility deve ser 'public' ou 'private'"
fi
if [ -n "$TEMPERATURE" ]; then
  case "$TEMPERATURE" in
    *[!0-9.]*|'') cv_die "--temperature deve ser um número entre 0.0 e 1.0" ;;
  esac
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$NAME" "$DESCRIPTION" "$SYSTEM_PROMPT" "$MODEL" "$TEMPERATURE" "$VISIBILITY" "$HANDLE" "$EXTRA" <<'PY'
import json, sys
name, desc, prompt, model, temp, vis, handle, extra = sys.argv[1:9]
p = {"name": name, "description": desc, "systemPrompt": prompt}
if model: p["modelName"] = model
if temp:  p["temperature"] = float(temp)
if vis:   p["visibility"] = vis
if handle: p["handle"] = handle
if extra:
    try:
        ex = json.loads(extra)
    except Exception as e:
        raise SystemExit("--json inválido: %s" % e)
    if not isinstance(ex, dict):
        raise SystemExit("--json deve ser um objeto JSON")
    p.update(ex)
print(json.dumps(p, ensure_ascii=False))
PY
)

cv_info "Novo agente:"
cv_info "  nome:        ${NAME}"
cv_info "  descrição:   ${DESCRIPTION}"
[ -n "$MODEL" ] && cv_info "  modelo:      ${MODEL}"
[ -n "$VISIBILITY" ] && cv_info "  visibilidade: ${VISIBILITY}"
cv_info ""

cv_confirm "Criar o agente '${NAME}'?"

rc=0
req_soft POST "/agents" "$PAYLOAD" || rc=$?
if [ "$rc" -ne 0 ]; then
  [ -n "$REQ_ERR" ] && printf '%s\n' "$REQ_ERR" >&2
  if [ "$rc" -eq 3 ]; then
    cv_die "402 USAGE_LIMIT: a organização/plano não permite criar novos agentes agora. Libere um agente existente ou faça upgrade do plano; a cota de agentes é por plano." 3
  fi
  exit "$rc"
fi

CREATED=$(cv_unwrap "$CV_RESP")

FORMATTER='
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print(json.dumps(d, ensure_ascii=False)); raise SystemExit
print("Agente criado.")
for k in ("id", "name", "modelName", "visibility", "handle"):
    if d.get(k) is not None:
        print("  %-12s %s" % (k + ":", d[k]))
'
cv_emit "$CREATED" "$FORMATTER"
