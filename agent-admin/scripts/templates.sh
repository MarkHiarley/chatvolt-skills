#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — templates
#
# Lista os modelos de agente publicados pela organização de templates
# (GET /agent-templates/{organizationId}). A rota só aceita o id da organização
# de templates configurada no Chatvolt: qualquer outro id responde 404. Nada é
# criado aqui; para criar um agente use create-agent.sh.
#
# Uso:
#   templates.sh [api-key] <organization-id> [--filter <regex>]
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
templates.sh — lista os templates de agente publicados

Uso:
  templates.sh [api-key] <organization-id> [--filter <regex>]

Argumentos:
  <organization-id>  id da organização de templates (só ela é aceita pela API;
                     outro id responde 404)

Opções:
  --filter <regex>   filtra por nome ou descrição (case-insensitive)
  -h, --help         mostra esta ajuda

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

ORG_ID=""
FILTER=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --filter)  [ "$#" -ge 2 ] || cv_die "--filter exige um valor"; FILTER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$ORG_ID" ]; then ORG_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$ORG_ID" ] || { usage >&2; cv_die "informe o id da organização de templates"; }

API_KEY=$(cv_req_key "$API_KEY_ARG")

cv_get "/agent-templates/${ORG_ID}"

# Resposta: {success, templates: [...], count}. O filtro é aplicado antes da
# formatação; o regex entra por sys.argv, nunca interpolado no código.
RAW=$(printf '%s' "$CV_RESP" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
flt = sys.argv[1]
rows = d.get("templates", []) if isinstance(d, dict) else []
if flt:
    rx = re.compile(flt, re.I)
    rows = [t for t in rows if rx.search(" ".join(str(t.get(k) or "") for k in ("name", "description")))]
print(json.dumps(rows, ensure_ascii=False))
' "$FILTER")

FORMATTER='
import json, sys
rows = json.load(sys.stdin)
hdr = "%-26s %-28s %-18s %s"
print(hdr % ("ID", "NOME", "MODELO", "DESCRIÇÃO"))
for t in rows:
    print(hdr % (
        str(t.get("id", ""))[:26],
        str(t.get("name", ""))[:28],
        str(t.get("modelName") or "-")[:18],
        str(t.get("description") or "-")[:60],
    ))
print("\nTotal: %d" % len(rows))
'

cv_emit "$RAW" "$FORMATTER"
