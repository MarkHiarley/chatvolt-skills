#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — send-audio
#
# AVISO: ENVIA UM ÁUDIO REAL para o cliente. Exige --yes explicitamente e nunca
# deve ser usado em teste automatizado.
#
# Uso:
#   send-audio.sh [api-key] <conversation-id> --audio-url <url> [--duration <segundos>] --yes
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
send-audio.sh — ENVIA um áudio real em uma conversa do Chatvolt

AVISO: ATENÇÃO: este script entrega um áudio de verdade ao cliente final.
    Ele exige --yes e NÃO é usado em testes (a rota é validada só no stub).

Uso:
  send-audio.sh [api-key] <conversation-id> --audio-url <url> [--duration <segundos>] --yes

Argumentos:
  <conversation-id>   id da conversa

Opções:
  --audio-url <url>   URL PÚBLICA do áudio (o Chatvolt baixa o arquivo; máx. 16 MB)
  --duration <n>      duração em segundos (inteiro) para o canal exibir o tempo
  --yes               confirma que você quer enviar o áudio ao cliente (obrigatório)
  -h, --help          mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Endpoint: POST /conversations/{conversationId}/send-audio {audioUrl, duration}

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CONV_ID=""
AUDIO_URL=""
DURATION=""
YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --audio-url) [ -n "${2:-}" ] || cv_die "--audio-url exige uma URL"; AUDIO_URL="$2"; shift 2 ;;
    --duration)  [ -n "${2:-}" ] || cv_die "--duration exige os segundos"; DURATION="$2"; shift 2 ;;
    --yes)       YES=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          cv_die "opção desconhecida: $1 (use --help)" ;;
    *)           if [ -z "$CONV_ID" ]; then CONV_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$CONV_ID" ] || { usage >&2; cv_die "informe o <conversation-id>"; }
[ -n "$AUDIO_URL" ] || { usage >&2; cv_die "informe --audio-url <url> (URL pública do áudio)"; }

if [ -n "$DURATION" ]; then
  case "$DURATION" in
    ''|*[!0-9]*) cv_die "--duration deve ser um número inteiro de segundos (recebido: '$DURATION')" ;;
  esac
fi

if [ "$YES" != "1" ]; then
  cv_die "esta chamada ENVIA um ÁUDIO REAL para o cliente final (rota POST /conversations/${CONV_ID}/send-audio). Se é isso mesmo que você quer, repita o comando com --yes. Em teste automatizado, use o stub — nunca um contato real."
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

cv_warn "ATENÇÃO: enviando um ÁUDIO REAL na conversa ${CONV_ID}"
cv_warn "audioUrl: ${AUDIO_URL}${DURATION:+ (duração ${DURATION}s)}"

BODY=$(python3 - "$AUDIO_URL" "$DURATION" <<'PY'
import json, sys
url, duration = sys.argv[1:3]
b = {"audioUrl": url}
if duration:
    b["duration"] = int(duration)
print(json.dumps(b, ensure_ascii=False))
PY
)

cv_request POST "/conversations/${CONV_ID}/send-audio" "$BODY"

cv_emit "$CV_RESP" 'import json,sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    data = d.get("data") if isinstance(d.get("data"), dict) else {}
    print("OK: áudio enviado (id %s)" % data.get("messageId", "?")) if data else print("OK:", d.get("success"))
else:
    print(d)'
