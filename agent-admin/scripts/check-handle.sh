#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — check-handle
#
# Verifica se um handle (identificador @usuario do agente) está livre
# (POST /agents/check-handle-available). Responde {available, agentId}: quando
# o handle já existe, agentId é o agente que o usa. Não cria nada.
#
# Regras do handle (validadas aqui antes da chamada): 3 a 30 caracteres, só
# letras, números e "_", sem "_" no início ou no fim. A API grava em minúsculas.
#
# Uso:
#   check-handle.sh [api-key] <handle>
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
check-handle.sh — verifica se um handle de agente está disponível

Uso:
  check-handle.sh [api-key] <handle>

Regras do handle: 3 a 30 caracteres; letras, números e "_";
sem "_" no início ou no fim. A API grava em minúsculas.

Saída: "disponível" ou "já usado pelo agente <id>". Exit 0 nos dois casos.

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

HANDLE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$HANDLE" ]; then HANDLE="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$HANDLE" ] || { usage >&2; cv_die "informe o handle (ex.: meu_agente)"; }

# Regras espelhadas do schema da API (CreateAgentSchema.handle).
HANDLE_ERR=$(python3 - "$HANDLE" <<'PY'
import re, sys
h = sys.argv[1]
if len(h) < 3: print("tem menos de 3 caracteres")
elif len(h) > 30: print("tem mais de 30 caracteres")
elif not re.fullmatch(r"[A-Za-z0-9_]+", h): print("aceita só letras, números e '_'")
elif h.startswith("_") or h.endswith("_"): print("não pode começar nem terminar com '_'")
PY
)
[ -z "$HANDLE_ERR" ] || cv_die "handle inválido: $HANDLE_ERR"

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$HANDLE" <<'PY'
import json, sys
print(json.dumps({"handle": sys.argv[1]}))
PY
)

cv_request POST "/agents/check-handle-available" "$PAYLOAD"

FORMATTER='
import json, sys
d = json.load(sys.stdin)
if d.get("available"):
    print("disponível")
else:
    print("já usado pelo agente %s" % (d.get("agentId") or "(id não informado)"))
'
cv_emit "$CV_RESP" "$FORMATTER"
