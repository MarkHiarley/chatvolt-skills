#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — submit-form
#
# Envia um formulário a um agente (POST /forms/{formId}/chat). O agente associado
# ao formulário recebe os campos e responde na conversa. É uma escrita (envia
# dados a um agente real), então pede confirmação (CV_YES=1 pula em testes).
#
# Contrato verificado no openapi.yaml: corpo { "form": { "fields": [ {label,value} ] } }.
#
# Uso:
#   submit-form.sh [api-key] <form-id> --field "Rótulo=Valor" [--field ...]
#                  [--json '<extra>'] [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1          pula a confirmação interativa
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
submit-form.sh — envia um formulário a um agente do Chatvolt

Uso:
  submit-form.sh [api-key] <form-id> --field "Rótulo=Valor" [--field ...]
                 [--json '<extra>'] [--yes]

Argumentos:
  <form-id>              id do formulário

Opções:
  --field "Rótulo=Valor" campo do formulário (repetível; o 1º '=' separa)
  --json '<extra>'       objeto JSON mesclado no objeto "form" (ex.: conver)
  --yes                  pula a confirmação
  -h, --help             mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY  API key (alternativa ao 1º argumento)
  CV_JSON=1         imprime somente JSON em stdout
  CV_YES=1          pula a confirmação interativa
  CV_API_BASE       base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

FORM_ID=""
EXTRA=""
FIELDS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --field)   [ "$#" -ge 2 ] || cv_die "--field exige 'Rótulo=Valor'"; FIELDS+=("$2"); shift 2 ;;
    --json)    [ "$#" -ge 2 ] || cv_die "--json exige um objeto JSON"; EXTRA="$2"; shift 2 ;;
    --yes)     export CV_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$FORM_ID" ]; then FORM_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$FORM_ID" ] || { usage >&2; cv_die "informe o id do formulário (<form-id>)"; }
[ "${#FIELDS[@]}" -ge 1 ] || { usage >&2; cv_die "informe ao menos um --field 'Rótulo=Valor'"; }

for f in "${FIELDS[@]}"; do
  case "$f" in
    *=*) : ;;
    *)   cv_die "--field deve ter o formato 'Rótulo=Valor' (recebido: $f)" ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$EXTRA" "${FIELDS[@]}" <<'PY'
import json, sys
extra = sys.argv[1]
fields = []
for raw in sys.argv[2:]:
    label, _, value = raw.partition("=")
    fields.append({"label": label, "value": value})
form = {"fields": fields}
if extra:
    try:
        ex = json.loads(extra)
    except Exception as e:
        raise SystemExit("--json inválido: %s" % e)
    if not isinstance(ex, dict):
        raise SystemExit("--json deve ser um objeto JSON")
    form.update(ex)
print(json.dumps({"form": form}, ensure_ascii=False))
PY
)

cv_info "Formulário: ${FORM_ID}"
for f in "${FIELDS[@]}"; do cv_info "  campo: ${f%%=*} = ${f#*=}"; done
cv_info ""

cv_confirm "Enviar o formulário ${FORM_ID} ao agente?"

cv_request POST "/forms/${FORM_ID}/chat" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict) and "data" in d and isinstance(d["data"], dict):
    d = d["data"]
if isinstance(d, dict):
    print("Formulário enviado.")
    for k in ("conversationId", "messageId", "status"):
        if d.get(k) is not None:
            print("  %-14s %s" % (k + ":", d[k]))
else:
    print(json.dumps(d, ensure_ascii=False))
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
