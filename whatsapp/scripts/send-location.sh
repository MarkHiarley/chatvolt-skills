#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-location
#
# Envia uma localização (pin no mapa) numa conversa
# (POST /messages/interactive/send-location).
#
# ATENÇÃO: esta rota ENVIA MENSAGEM REAL no WhatsApp (Z-API/Zapper) do contato.
#
# Uso:
#   send-location.sh [api-key] --conversation <conversationId> --latitude <dec>
#                    --longitude <dec> --name <local> --address <endereço>
#                    [--agent <agentId>] --yes
#
# Ambiente:
#   CHATVOLT_API_KEY / CHATVOLT_AGENT_ID   alternativas aos argumentos
#   CV_JSON=1    imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1     equivale a --yes
#   CV_API_BASE  sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-location.sh — envia uma localização no WhatsApp (envio REAL)

Uso:
  send-location.sh [api-key] --conversation <conversationId> --latitude <dec>
                   --longitude <dec> --name <local> --address <endereço>
                   [--agent <agentId>] --yes

Campos obrigatórios do contrato (POST /messages/interactive/send-location):
  agentId, conversationId, latitude, longitude, name, address

Opções:
  --conversation <id>   (obrigatório) id da conversa (conversationId)
  --latitude <dec>      (obrigatório) latitude como STRING decimal (ex.: -23.5505)
  --longitude <dec>     (obrigatório) longitude como STRING decimal (ex.: -46.6333)
  --name <local>        (obrigatório) nome do local (name)
  --address <endereço>  (obrigatório) endereço exibido no pin (address)
  --agent <id>          agentId responsável (ou CHATVOLT_AGENT_ID)
  -y, --yes             confirma o ENVIO REAL (obrigatório)
  -h, --help            mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   agentId (alternativa ao --agent)
  CV_JSON=1           imprime somente JSON em stdout
  CV_YES=1            equivale a --yes
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

AGENT_ID_ARG=""
CONVERSATION_ID=""
LATITUDE=""
LONGITUDE=""
PLACE_NAME=""
ADDRESS=""
YES=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent) AGENT_ID_ARG="${2:-}"; shift 2 ;;
    --conversation) CONVERSATION_ID="${2:-}"; shift 2 ;;
    --latitude) LATITUDE="${2:-}"; shift 2 ;;
    --longitude) LONGITUDE="${2:-}"; shift 2 ;;
    --name) PLACE_NAME="${2:-}"; shift 2 ;;
    --address) ADDRESS="${2:-}"; shift 2 ;;
    -y|--yes) YES=1; shift ;;
    --) shift; break ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *) usage >&2; cv_die "argumento inesperado: $1" ;;
  esac
done

# ── Validação de campos (contrato do openapi.yaml) ───────────────────────
AGENT_ID="${AGENT_ID_ARG:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$CONVERSATION_ID" ] || { usage >&2; cv_die "--conversation <conversationId> é obrigatório (contrato: conversationId)"; }
[ -n "$LATITUDE" ] || { usage >&2; cv_die "--latitude <dec> é obrigatório (contrato: latitude)"; }
[ -n "$LONGITUDE" ] || { usage >&2; cv_die "--longitude <dec> é obrigatório (contrato: longitude)"; }
[ -n "$PLACE_NAME" ] || { usage >&2; cv_die "--name <local> é obrigatório (contrato: name)"; }
[ -n "$ADDRESS" ] || { usage >&2; cv_die "--address <endereço> é obrigatório (contrato: address)"; }
[ -n "$AGENT_ID" ] || { usage >&2; cv_die "--agent <agentId> é obrigatório (contrato: agentId; ou exporte CHATVOLT_AGENT_ID)"; }

python3 - "$LATITUDE" "$LONGITUDE" <<'PY' || cv_die "coordenadas inválidas (contrato: latitude/longitude como string decimal)"
import sys
lat, lon = sys.argv[1], sys.argv[2]
for label, value, lo, hi in (("--latitude", lat, -90.0, 90.0), ("--longitude", lon, -180.0, 180.0)):
    try:
        num = float(value)
    except ValueError:
        print(label + " inválida: " + repr(value) + " (use string decimal, ex.: -23.5505)", file=sys.stderr)
        raise SystemExit(1)
    if not lo <= num <= hi:
        print(label + " fora do intervalo " + str(lo) + ".." + str(hi) + ": " + value, file=sys.stderr)
        raise SystemExit(1)
PY

# ── Confirmação de ENVIO REAL ────────────────────────────────────────────
if [ "$YES" != "1" ] && [ "${CV_YES:-0}" != "1" ]; then
  cv_die "recusado: esta rota ENVIA uma mensagem real no WhatsApp do contato da conversa ${CONVERSATION_ID}. Rode com --yes para confirmar (ou CV_YES=1)."
fi
cv_warn "ENVIO REAL: a localização '${PLACE_NAME}' (${LATITUDE}, ${LONGITUDE}) será entregue no WhatsApp do contato da conversa ${CONVERSATION_ID}."

API_KEY=$(cv_req_key "$API_KEY_ARG")

PAYLOAD=$(python3 - "$AGENT_ID" "$CONVERSATION_ID" "$LATITUDE" "$LONGITUDE" "$PLACE_NAME" "$ADDRESS" <<'PY'
import json, sys
agent, conv, lat, lon, name, address = sys.argv[1:7]
p = {"agentId": agent, "conversationId": conv, "latitude": lat, "longitude": lon,
     "name": name, "address": address}
print(json.dumps(p, ensure_ascii=False))
PY
) || cv_die "não consegui montar o payload da localização"

cv_request POST "/messages/interactive/send-location" "$PAYLOAD"

FORMATTER='
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print(raw.strip() or "resposta vazia"); raise SystemExit
if isinstance(d, dict):
    print("Localização enviada.")
    if d.get("messageId"):
        print("  id:     " + str(d["messageId"]))
    if d.get("status"):
        print("  status: " + str(d["status"]))
    if not d.get("messageId") and not d.get("status"):
        print(json.dumps(d, ensure_ascii=False))
else:
    print(json.dumps(d, ensure_ascii=False))
'
cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
