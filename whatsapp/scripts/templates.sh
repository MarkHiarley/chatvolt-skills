#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — whatsapp/templates
#
# Lista e cria templates de mensagem da WABA (WhatsApp Business Account)
# associada ao agente.
#
# Uso:
#   templates.sh [api-key] list   --agent <agentId> [--status <approved|rejected|pending>]
#   templates.sh [api-key] create --agent <agentId> --name <nome> --category <c> --language <lang>
#                                 (--body <texto> | --components '<json-array>')
#                                 [--header <texto>] [--footer <texto>] [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY    alternativa à api-key como 1º argumento
#   CHATVOLT_AGENT_ID   alternativa ao --agent
#   CV_JSON=1           imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1            pula a confirmação do create
#   CV_API_BASE         sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
templates.sh — templates de mensagem do WhatsApp (Meta/WABA)

Uso:
  templates.sh [api-key] list   --agent <agentId> [--status <approved|rejected|pending>]
  templates.sh [api-key] create --agent <agentId> --name <nome> --category <c> --language <lang>
                                (--body <texto> | --components '<json-array>')
                                [--header <texto>] [--footer <texto>] [--yes]

Subcomandos:
  list      GET /whatsapp/templates — lista os templates da WABA do agente
            (o contrato exige agentId na query; agente sem WhatsApp → 400)
  create    POST /whatsapp/templates — cria um template e o envia para
            aprovação da Meta (não existe rota de exclusão). Exige --yes.

Opções:
  --agent <id>        agentId dono dos templates (ou CHATVOLT_AGENT_ID)
  --status <s>        (list) filtra por status: approved, rejected, pending
  --name <nome>       (create) nome do template (minúsculas, números e _)
  --category <c>      (create) MARKETING | UTILITY | AUTHENTICATION
  --language <lang>   (create) código do idioma, ex.: pt_BR
  --body <texto>      (create) corpo da mensagem (componente BODY)
  --header <texto>    (create) cabeçalho (componente HEADER, texto)
  --footer <texto>    (create) rodapé (componente FOOTER)
  --components <json> (create) array JSON de componentes (substitui --body/--header/--footer;
                      use para variáveis: {"type":"BODY","text":"Olá {{1}}",
                      "example":{"body_text":[["João"]]}})
  -y, --yes           (create) confirma a criação sem perguntar
  -h, --help          mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   agentId (alternativa ao --agent)
  CV_JSON=1           imprime somente JSON em stdout
  CV_YES=1            equivale a --yes no create
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

[ "$#" -gt 0 ] || { usage >&2; cv_die "informe o subcomando (list|create)"; }
CMD="$1"; shift
case "$CMD" in
  list|create) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; cv_die "subcomando inválido: ${CMD} (use list ou create)" ;;
esac

require_create() { [ "$CMD" = "create" ] || cv_die "$1 só vale para o subcomando create"; }

AGENT_ID_ARG=""
STATUS=""
NAME=""
CATEGORY=""
LANGUAGE=""
HEADER=""
BODY=""
FOOTER=""
COMPONENTS=""
YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent) AGENT_ID_ARG="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --name) require_create "--name"; NAME="${2:-}"; shift 2 ;;
    --category) require_create "--category"; CATEGORY="${2:-}"; shift 2 ;;
    --language) require_create "--language"; LANGUAGE="${2:-}"; shift 2 ;;
    --header) require_create "--header"; HEADER="${2:-}"; shift 2 ;;
    --body) require_create "--body"; BODY="${2:-}"; shift 2 ;;
    --footer) require_create "--footer"; FOOTER="${2:-}"; shift 2 ;;
    --components) require_create "--components"; COMPONENTS="${2:-}"; shift 2 ;;
    -y|--yes) require_create "--yes"; YES=1; shift ;;
    --) shift; break ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *) usage >&2; cv_die "argumento inesperado: $1" ;;
  esac
done

# ── Validação de campos (contrato do openapi.yaml) ───────────────────────
# GET /whatsapp/templates: agentId é required (na query).
# POST /whatsapp/templates: agentId, name, category, language, components.
AGENT_ID="${AGENT_ID_ARG:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "informe --agent <agentId> (contrato: agentId é obrigatório; ou exporte CHATVOLT_AGENT_ID)"; }

if [ "$CMD" = "list" ]; then
  if [ -n "$STATUS" ]; then
    case "$(printf '%s' "$STATUS" | tr '[:upper:]' '[:lower:]')" in
      approved|rejected|pending) STATUS=$(printf '%s' "$STATUS" | tr '[:upper:]' '[:lower:]') ;;
      *) cv_die "--status inválido: ${STATUS} (use approved, rejected ou pending)" ;;
    esac
  fi
else
  [ -n "$NAME" ] || { usage >&2; cv_die "--name <nome> é obrigatório (contrato: name)"; }
  [[ "$NAME" =~ ^[a-z0-9_]+$ ]] || cv_die "--name inválido: use só minúsculas, números e _ (a Meta recusa maiúsculas, espaços e hífen)"
  [ -n "$CATEGORY" ] || { usage >&2; cv_die "--category <c> é obrigatório (contrato: category)"; }
  case "$CATEGORY" in
    MARKETING|UTILITY|AUTHENTICATION) ;;
    *) cv_die "categoria inválida: ${CATEGORY} (use MARKETING, UTILITY ou AUTHENTICATION)" ;;
  esac
  [ -n "$LANGUAGE" ] || { usage >&2; cv_die "--language <lang> é obrigatório (contrato: language; ex.: pt_BR)"; }
  [ -n "$BODY" ] || [ -n "$COMPONENTS" ] || { usage >&2; cv_die "informe --body <texto> ou --components '<json-array>' (contrato: components)"; }
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

# ── list ────────────────────────────────────────────────────────────────
if [ "$CMD" = "list" ]; then
  cv_request GET "/whatsapp/templates" "" -G --data-urlencode "agentId=${AGENT_ID}"

  # O contrato documenta {data:[...]}; a página narrativa mostra {templates:[...]}.
  NORM=$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
status = (sys.argv[1] or "").lower()
try:
    d = json.load(sys.stdin)
except Exception:
    print("[]"); raise SystemExit
if isinstance(d, dict):
    for k in ("data", "templates"):
        if isinstance(d.get(k), list):
            d = d[k]; break
if not isinstance(d, list):
    d = []
if status:
    d = [t for t in d if str(t.get("status", "")).lower() == status]
print(json.dumps(d, ensure_ascii=False))
' "$STATUS"
)

  FORMATTER='
import json, sys
items = json.load(sys.stdin)
if not items:
    print("Nenhum template encontrado.")
    raise SystemExit
wname = max(len(str(t.get("name") or "")) for t in items)
wname = max(wname, 4)
print(str(len(items)) + " template(s):")
print("  " + "NOME".ljust(wname) + "  " + "IDIOMA".ljust(6) + "  " + "STATUS".ljust(9) + "  " + "CATEGORIA".ljust(14) + "  ID")
for t in items:
    print("  " + str(t.get("name") or "").ljust(wname) + "  "
          + str(t.get("language") or "").ljust(6) + "  "
          + str(t.get("status") or "").ljust(9) + "  "
          + str(t.get("category") or "").ljust(14) + "  "
          + str(t.get("id") or ""))
'
  cv_emit "$NORM" "$FORMATTER"
  exit 0
fi

# ── create ──────────────────────────────────────────────────────────────
cv_warn "ATENÇÃO: o template '${NAME}' será criado na WABA do agente ${AGENT_ID} e enviado para aprovação da Meta (não há como apagar pela API)."
if [ "$YES" != "1" ]; then
  cv_confirm "Criar o template '${NAME}' (${CATEGORY}/${LANGUAGE}) e enviá-lo para aprovação da Meta?"
fi

PAYLOAD=$(python3 - "$AGENT_ID" "$NAME" "$CATEGORY" "$LANGUAGE" "$HEADER" "$BODY" "$FOOTER" "$COMPONENTS" <<'PY'
import json, sys
agent, name, category, language, header, body, footer, comps_raw = sys.argv[1:9]
if comps_raw:
    try:
        comps = json.loads(comps_raw)
    except Exception:
        print("--components não é JSON válido", file=sys.stderr); raise SystemExit(1)
    if not isinstance(comps, list) or not comps:
        print("--components precisa ser um array JSON não vazio", file=sys.stderr); raise SystemExit(1)
else:
    comps = []
    if header:
        comps.append({"type": "HEADER", "format": "TEXT", "text": header})
    comps.append({"type": "BODY", "text": body})
    if footer:
        comps.append({"type": "FOOTER", "text": footer})
p = {"agentId": agent, "name": name, "category": category, "language": language, "components": comps}
print(json.dumps(p, ensure_ascii=False))
PY
) || cv_die "não consegui montar o payload de components"

cv_request POST "/whatsapp/templates" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("Template criado:")
    print("  nome:   " + str(d.get("name") or "-"))
    print("  id:     " + str(d.get("id") or "-"))
    print("  status: " + str(d.get("status") or "-") + "  (a aprovação da Meta é assíncrona)")
else:
    print(json.dumps(d, ensure_ascii=False))
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
