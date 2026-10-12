#!/usr/bin/env bash
set -euo pipefail
#
# Chatvolt — liga/desliga o webhook de um serviço de mensageria do agente
#
# Uso: ./toggle-webhook.sh <api-key> <agent-id> <whatsapp|telegram|zapi|instagram> <on|off>
#
# Contrato REAL: PATCH /agents/{id}/webhook?type=<tipo>&enabled=<bool> — toggle,
# SEM body. A doc antiga (`POST /agents/{id}/webhook` com JSON) não existe.
# Ver SOURCES.md na raiz do repositório.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<'EOF'
Uso: toggle-webhook.sh <api-key> <agent-id> <tipo> <on|off>

Liga/desliga o webhook de um serviço de mensageria do agente.
É um TOGGLE de status — não configura URL (a URL do webhook é configurada
na plataforma). Requisição: PATCH /agents/{id}/webhook?type=<tipo>&enabled=<bool>,
sem body.

Argumentos:
  <api-key>    API key do Chatvolt (ou exporte CHATVOLT_API_KEY)
  <agent-id>   ID do agente
  <tipo>       whatsapp | telegram | zapi | instagram
  <estado>     on  (enabled=true)  |  off (enabled=false)
               (também aceita true/false, enable/disable)

Comportamento:
  - Se o agente não tiver esse service provider conectado, a API responde
    HTTP 404 "ServiceProvider not found for this agent." — o erro é mostrado
    de forma legível (sem stacktrace) e o script sai com código 1.
  - Sempre pede confirmação (CV_YES=1 ou --yes pula); o toggle muda o
    estado real do canal no agente.

Observação importante:
  Para o tipo `instagram`, ligar/desligar o webhook também controla as
  configurações `answerDms` e `answerComments` do agente.

Opções:
  -h, --help   Esta ajuda

Saída:
  A resposta textual da API em stdout; diagnósticos em stderr.
  Com CV_JSON=1 imprime SOMENTE JSON em stdout (se a API devolver texto puro,
  sai como {"raw": "..."}).

Exit codes:
  0 ok · 1 erro de cliente (tipo/estado inválido, 404, 400) · 3 quota (402)
  · 4 rede · 5 servidor · 130 cancelado

Exemplos:
  toggle-webhook.sh "$CHATVOLT_API_KEY" <agent-id> whatsapp off
  toggle-webhook.sh "$CHATVOLT_API_KEY" <agent-id> telegram on
EOF
}

POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) cv_die "opção desconhecida: $1 (use --help)" ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
AGENT_ID="${POS[1]:-}"
TYPE="${POS[2]:-}"
STATE="${POS[3]:-}"

[ -n "$AGENT_ID" ] || cv_die "informe o agent-id: toggle-webhook.sh <api-key> <agent-id> <tipo> <on|off>"
[ -n "$TYPE" ] || cv_die "informe o tipo: whatsapp | telegram | zapi | instagram"
[ -n "$STATE" ] || cv_die "informe o estado: on | off"

case "$TYPE" in
  whatsapp|telegram|zapi|instagram) : ;;
  *) cv_die "tipo inválido: '${TYPE}' — use whatsapp, telegram, zapi ou instagram" ;;
esac

case "$(printf '%s' "$STATE" | tr '[:upper:]' '[:lower:]')" in
  on|true|enable|enabled|1) ENABLED=true; STATE_LABEL="ligar (enabled=true)" ;;
  off|false|disable|disabled|0) ENABLED=false; STATE_LABEL="desligar (enabled=false)" ;;
  *) cv_die "estado inválido: '${STATE}' — use on ou off" ;;
esac

echo "Webhook do agente ${AGENT_ID}: ${STATE_LABEL} o serviço '${TYPE}'" >&2
echo "Requisição: PATCH /agents/${AGENT_ID}/webhook?type=${TYPE}&enabled=${ENABLED} (sem body)" >&2
if [ "$TYPE" = "instagram" ]; then
  cv_warn "instagram: este toggle também altera answerDms e answerComments do agente"
fi

cv_confirm "Confirmar ${STATE_LABEL} o webhook de '${TYPE}' no agente ${AGENT_ID}?"

Path="/agents/${AGENT_ID}/webhook?type=${TYPE}&enabled=${ENABLED}"
cv_request PATCH "$Path"

if printf '%s' "$CV_RESP" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null; then
  cv_emit "$CV_RESP" '
import json, sys

raw = json.load(sys.stdin)
if isinstance(raw, dict) and (raw.get("error") or raw.get("success") is False):
    print("❌ a API retornou erro: " + json.dumps(raw.get("error") or raw, ensure_ascii=False))
    raise SystemExit(1)

d = raw
if isinstance(raw, dict) and isinstance(raw.get("data"), dict):
    d = raw["data"]

print("✅ webhook atualizado")
if isinstance(d, dict):
    if d.get("id"):
        print("   Agente:  " + str(d.get("id")))
    if d.get("webhookType"):
        print("   Serviço: " + str(d.get("webhookType")))
    if d.get("webhookEnabled") is not None:
        print("   Webhook: " + ("ligado" if d.get("webhookEnabled") else "desligado"))
    if d.get("updatedAt"):
        print("   Atualizado: " + str(d.get("updatedAt")))
    if not any(k in d for k in ("webhookType", "webhookEnabled")):
        print(json.dumps(raw, ensure_ascii=False, indent=2))
else:
    print(json.dumps(raw, ensure_ascii=False))
'
else
  if [ "$CV_JSON" = "1" ]; then
    printf '%s' "$CV_RESP" | python3 -c 'import json, sys; print(json.dumps({"raw": sys.stdin.read().strip()}, ensure_ascii=False))'
  else
    printf '%s\n' "$CV_RESP"
  fi
fi
