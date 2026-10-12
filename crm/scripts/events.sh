#!/usr/bin/env bash
# events.sh — escuta os eventos de CRM em tempo real (SSE) do Chatvolt.
#
# Rota: GET /crm/events[?scenarioId=…]  ->  text/event-stream (SSE)
#
# Medido ao vivo (2026-10-12): o servidor envia
#   data: {"type":"CONNECTED","channel":"crm:<orgId>:<scenarioId>"}
# e mantém a conexão aberta INDEFINIDAMENTE (sem eventos se não houver atividade).
# Por isso o script usa `curl -N` (sem buffer) com `--max-time` (padrão 30s) e
# encerra LIMPO com exit 0 quando o tempo acaba ou o servidor fecha o stream.
#
# O SSE do Chatvolt traz um objeto JSON por linha `data:`; linhas `event:`/`id:`
# e comentários são ignorados (o formato completo de SSE não é interpretado).
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: events.sh <api-key> --scenario <scenario-id> [--max-time <segundos>] [--raw]

Escuta GET /crm/events (SSE) e imprime os eventos recebidos.

Opções:
  --scenario <id>     cenário cujos eventos serão escutados (scenarioId).
                      OBRIGATÓRIO: sem ele a API responde 400 na hora
                      {"error":"scenarioId is required"} (medido ao vivo).
  --max-time <s>      tempo máximo conectado, em segundos (padrão 30; mínimo 1).
                      A conexão SSE fica aberta indefinidamente; ao esgotar o
                      tempo o script encerra limpo (exit 0).
  --raw               imprime os bytes SSE crus (sem formatação) — tem
                      precedência sobre CV_JSON=1
  -h, --help          mostra esta ajuda

Saída:
  padrão (humano)     uma linha por evento: "[n] TIPO  {json do evento}"
  CV_JSON=1           um objeto JSON por linha (NDJSON) em stdout
Diagnósticos e o resumo (quantidade de eventos) vão para stderr.

Exemplos:
  events.sh "$CHATVOLT_API_KEY" --scenario cmpwwpn1r04hl12pfoglarith --max-time 20
  CV_JSON=1 events.sh "$CHATVOLT_API_KEY" --scenario "$SC" --max-time 5
  events.sh "$CHATVOLT_API_KEY" --scenario "$SC" --raw | head -3

Exit: 0 ok (inclusive ao fim do --max-time) · 1 erro de cliente · 3 quota (402) ·
      4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage >&2; exit 1; }

POS=()
SC=""
MAX_TIME=30
RAW=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --scenario) [ -n "${2:-}" ] || { usage >&2; cv_die "--scenario exige o id do cenário"; }
                SC="$2"; shift 2 ;;
    --max-time) [ -n "${2:-}" ] || { usage >&2; cv_die "--max-time exige segundos (inteiro >= 1)"; }
                case "$2" in ''|*[!0-9]*) cv_die "--max-time exige um inteiro em segundos (>= 1)";; esac
                [ "$2" -ge 1 ] || cv_die "--max-time exige um inteiro em segundos (>= 1)"
                MAX_TIME="$2"; shift 2 ;;
    --raw) RAW=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) usage >&2; cv_die "opção desconhecida: $1" ;;
    *)  POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
[ -n "$SC" ] || { usage >&2; cv_die "--scenario é obrigatório (a API responde 400 sem scenarioId)"; }

PATH_Q="/crm/events?scenarioId=${SC}"

# Filtro do stream: formata cada linha `data:` e guarda uma cópia crua do corpo
# (usada para reportar erros HTTP que não vêm em formato SSE).
read -r -d '' FILTER <<'PY' || true
import json, sys

mode, copy_path = sys.argv[1], sys.argv[2]
n = 0
with open(copy_path, "w", encoding="utf-8") as fh:
    for line in sys.stdin:
        fh.write(line)
        raw = line.rstrip("\n")
        if not raw.startswith("data:"):
            continue
        payload = raw[5:].strip()
        try:
            d = json.loads(payload)
        except Exception:
            d = {"raw": payload}
        n += 1
        if mode == "json":
            sys.stdout.write(json.dumps(d, ensure_ascii=False) + "\n")
        else:
            kind = d.get("type") or d.get("event") or "EVENTO"
            sys.stdout.write("[%02d] %-14s %s\n" % (n, kind, json.dumps(d, ensure_ascii=False)))
        sys.stdout.flush()
print("%d evento(s) recebido(s) no stream SSE" % n, file=sys.stderr)
PY

MODE=human
if [ "$CV_JSON" = "1" ]; then MODE=json; fi

TMPD="$(mktemp -d)" || cv_die "não foi possível criar diretório temporário"
trap 'rm -rf "$TMPD"' EXIT
HDRS="$TMPD/headers.txt"
BODY="$TMPD/stream.txt"
CURL_ERR="$TMPD/curl.err"

cv_warn "escutando GET /crm/events (SSE) do cenário ${SC} — encerra em ${MAX_TIME}s"

RC=0
set +e
if [ "$RAW" = 1 ]; then
  curl -sS -N -D "$HDRS" --max-time "$MAX_TIME" -H "Authorization: Bearer ${API_KEY}" \
    "${CV_BASE_URL}${PATH_Q}" 2>"$CURL_ERR" | tee "$BODY"
  RC=${PIPESTATUS[0]}
else
  curl -sS -N -D "$HDRS" --max-time "$MAX_TIME" -H "Authorization: Bearer ${API_KEY}" \
    "${CV_BASE_URL}${PATH_Q}" 2>"$CURL_ERR" | python3 -u -c "$FILTER" "$MODE" "$BODY"
  RC=${PIPESTATUS[0]}
fi
set -e

# curl 28 = --max-time esgotado (fim normal do stream); 0 = servidor fechou.
case "$RC" in
  0|28) ;;
  130) cv_die "cancelado pelo usuário" 130 ;;
  *)   cv_die "falha de rede ao abrir o stream SSE (curl exit ${RC}): $(head -1 "$CURL_ERR" 2>/dev/null)" 4 ;;
esac

if [ "$RC" != "28" ] && [ -s "$CURL_ERR" ]; then
  cv_warn "curl: $(head -1 "$CURL_ERR")"
fi

CODE=$(awk 'NR==1 {print $2}' "$HDRS" 2>/dev/null || true)
case "$CODE" in
  200) ;;
  "")  cv_warn "nenhum cabeçalho HTTP capturado (curl exit ${RC})" ;;
  401|403) cv_die "HTTP ${CODE} (não autorizado): $(cv_err_msg "$(cat "$BODY")") — confira a API key e as permissões da organização" ;;
  402) cv_die "HTTP 402 (quota): limite de uso mensal do plano atingido — $(cv_err_msg "$(cat "$BODY")")" 3 ;;
  404) cv_die "HTTP 404 (não encontrado): $(cv_err_msg "$(cat "$BODY")")" ;;
  5*)  cv_die "HTTP ${CODE} (erro interno do servidor): $(cv_err_msg "$(cat "$BODY")")" 5 ;;
  *)   cv_die "HTTP ${CODE}: $(cv_err_msg "$(cat "$BODY")")" ;;
esac

# stderr: o stdout do events.sh carrega só o stream de eventos (usável em pipe).
if [ "$RC" = "28" ]; then
  cv_warn "tempo esgotado (--max-time ${MAX_TIME}s): stream encerrado."
else
  cv_warn "stream encerrado pelo servidor."
fi
