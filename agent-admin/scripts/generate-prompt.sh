#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — generate-prompt
#
# Gera o systemPrompt de um agente a partir dos campos de comportamento
# (POST /agents/generate-prompt, rota pública: aceita API key). A IA é a da
# organização (ou a do sistema, como fallback). Se a geração falhar, a rota
# devolve um prompt montado com os campos — por isso a resposta sempre traz
# systemPrompt. Limite: 10 chamadas/min por organização (429 tem retry automático).
#
# Uso:
#   generate-prompt.sh [api-key] --agent-name <n> [--company <c>] [--sector <s>]
#                      [--objective <o>] [--audience <p>] [--actions <a>] [--limits <l>]
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
generate-prompt.sh — gera o prompt de sistema de um agente

Uso:
  generate-prompt.sh [api-key] --agent-name <n> [--company <c>] [--sector <s>]
                     [--objective <o>] [--audience <p>] [--actions <a>] [--limits <l>]

Opções:
  --agent-name <n>   nome do agente (obrigatório; até 200 caracteres)
  --company <c>      nome da empresa (até 200)
  --sector <s>       setor de atuação (até 200)
  --objective <o>    objetivo principal (até 300)
  --audience <p>     público-alvo (até 2000)
  --actions <a>      ações do agente (até 2000)
  --limits <l>       limites do agente: o que ele não deve fazer (até 2000)
  -h, --help         mostra esta ajuda

Saída: o prompt gerado em stdout (CV_JSON=1 devolve {"systemPrompt": "..."}).

Ambiente:
  CHATVOLT_API_KEY  API key (alternativa ao 1º argumento)
  CV_JSON=1         imprime somente JSON em stdout
  CV_API_BASE       base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

AGENT_NAME=""
COMPANY=""
SECTOR=""
OBJECTIVE=""
AUDIENCE=""
ACTIONS=""
LIMITS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent-name) [ "$#" -ge 2 ] || cv_die "--agent-name exige um valor"; AGENT_NAME="$2"; shift 2 ;;
    --company)    [ "$#" -ge 2 ] || cv_die "--company exige um valor"; COMPANY="$2"; shift 2 ;;
    --sector)     [ "$#" -ge 2 ] || cv_die "--sector exige um valor"; SECTOR="$2"; shift 2 ;;
    --objective)  [ "$#" -ge 2 ] || cv_die "--objective exige um valor"; OBJECTIVE="$2"; shift 2 ;;
    --audience)   [ "$#" -ge 2 ] || cv_die "--audience exige um valor"; AUDIENCE="$2"; shift 2 ;;
    --actions)    [ "$#" -ge 2 ] || cv_die "--actions exige um valor"; ACTIONS="$2"; shift 2 ;;
    --limits)     [ "$#" -ge 2 ] || cv_die "--limits exige um valor"; LIMITS="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           cv_die "opção desconhecida: $1 (use --help)" ;;
    *)            cv_die "argumento extra: $1" ;;
  esac
done

[ -n "$AGENT_NAME" ] || { usage >&2; cv_die "--agent-name é obrigatório"; }

# Limites da rota (zod), medidos em caracteres antes de gastar uma chamada de LLM.
check_len() { [ "${#2}" -le "$3" ] || cv_die "$1 excede $3 caracteres"; }
check_len "--agent-name" "$AGENT_NAME" 200
check_len "--company" "$COMPANY" 200
check_len "--sector" "$SECTOR" 200
check_len "--objective" "$OBJECTIVE" 300
check_len "--audience" "$AUDIENCE" 2000
check_len "--actions" "$ACTIONS" 2000
check_len "--limits" "$LIMITS" 2000

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$AGENT_NAME" "$COMPANY" "$SECTOR" "$OBJECTIVE" "$AUDIENCE" "$ACTIONS" "$LIMITS" <<'PY'
import json, sys
name, company, sector, objective, audience, actions, limits = sys.argv[1:8]
print(json.dumps({
    "agentName": name,
    "companyName": company,
    "sector": sector,
    "objective": objective,
    "publicoAlvo": audience,
    "acoes": actions,
    "limites": limits,
}, ensure_ascii=False))
PY
)

cv_info "Gerando prompt para '${AGENT_NAME}'..."
cv_request POST "/agents/generate-prompt" "$PAYLOAD"

if [ "$CV_JSON" = "1" ]; then
  printf '%s\n' "$CV_RESP"
  exit 0
fi

PROMPT=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("systemPrompt") or "")')
[ -n "$PROMPT" ] || cv_die "a API não devolveu systemPrompt: $(cv_err_msg "$CV_RESP")"
printf '%s\n' "$PROMPT"
