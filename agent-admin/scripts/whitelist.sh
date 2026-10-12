#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — whitelist (WhatsApp)
#
# Gerencia a whitelist de WhatsApp de um agente:
#   list   <agent-id>                 GET    /agent-whitelist-whatsapp/{agent-id}
#   add    <agent-id> <num> [<num>…]  POST   /agent-whitelist-whatsapp
#   update <agent-id> <antigo> <novo> PATCH  /agent-whitelist-whatsapp/{agent-id}
#   remove <agent-id> <num>           DELETE /agent-whitelist-whatsapp/{agent-id}
#
# A rota é no plural (whatsapp) e o corpo identifica o agente por `agentId`.
# Um 404 costuma significar agente inexistente (ou número não encontrado na
# remoção/atualização) — a mensagem abaixo explica o que conferir.
#
# Uso:
#   whitelist.sh [api-key] <list|add|update|remove> ... [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1          pula a confirmação interativa
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
whitelist.sh — gerencia a whitelist de WhatsApp de um agente

Uso:
  whitelist.sh [api-key] list   <agent-id>
  whitelist.sh [api-key] add    <agent-id> <numero> [<numero> ...]
  whitelist.sh [api-key] update <agent-id> <numero-antigo> <numero-novo>
  whitelist.sh [api-key] remove <agent-id> <numero>

Comandos:
  list     lista os números liberados do agente (GET /agent-whitelist-whatsapp/{id})
  add      adiciona um ou mais números (POST /agent-whitelist-whatsapp)
  update   troca um número por outro (PATCH /agent-whitelist-whatsapp/{id})
  remove   remove um número (DELETE /agent-whitelist-whatsapp/{id}) — pede confirmação

Opções:
  --yes      pula a confirmação (update/remove)
  -h, --help mostra esta ajuda

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
# e devolve o exit code, com o stderr do cv_request em REQ_ERR (para tratar 404).
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

# propaga_erro <agent-id> — usa o $rc da última req_soft: explica 404 e encerra.
propaga_erro() {
  if [ "$rc" -eq 1 ] && [ "$CV_STATUS" = "404" ]; then
    printf '%s\n' "$REQ_ERR" >&2
    cv_die "404 na whitelist de WhatsApp: o agente '$1' provavelmente não existe (ou o número não está na whitelist, em remove/update). Confira o id com ./agent-admin/scripts/list-agents.sh."
  fi
  [ -n "$REQ_ERR" ] && printf '%s\n' "$REQ_ERR" >&2
  exit "$rc"
}

# Normaliza os argumentos: --yes e -h/--help são reconhecidos em qualquer posição
# (o resto vira argumento posicional, sem risco de virar número da whitelist).
ARGS=()
for _a in "$@"; do
  case "$_a" in
    --yes)     export CV_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         ARGS+=("$_a") ;;
  esac
done
set -- "${ARGS[@]}"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

CMD=""
if [ "$#" -gt 0 ]; then
  case "$1" in
    -*) cv_die "comando desconhecido: $1 (use list|add|update|remove, ou --help)" ;;
    *)  CMD="$1"; shift ;;
  esac
fi

case "$CMD" in
  list|add|update|remove) : ;;
  *) usage >&2; cv_die "informe um comando: list | add | update | remove" ;;
esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

case "$CMD" in
  list)
    AGENT_ID="${1:-}"; shift || true
    [ -n "$AGENT_ID" ] || { usage >&2; cv_die "list exige <agent-id>"; }
    rc=0; req_soft GET "/agent-whitelist-whatsapp/${AGENT_ID}" || rc=$?
    [ "$rc" -eq 0 ] || propaga_erro "$AGENT_ID"
    FORMATTER='
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, list):
    print(json.dumps(d, ensure_ascii=False)); raise SystemExit
print("%-40s %s" % ("AGENTE", "NUMERO WHATSAPP"))
for e in d:
    if isinstance(e, dict):
        print("%-40s %s" % (e.get("agentId", ""), e.get("whatsappNumber", "")))
print("\nTotal: %d" % len(d))
'
    cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
    ;;

  add)
    AGENT_ID="${1:-}"; shift || true
    [ -n "$AGENT_ID" ] || { usage >&2; cv_die "add exige <agent-id> <numero> [<numero> ...]"; }
    [ "$#" -ge 1 ] || { usage >&2; cv_die "add exige ao menos um número"; }
    PAYLOAD=$(python3 - "$AGENT_ID" "$@" <<'PY'
import json, sys
nums = sys.argv[2:]
payload = {"agentId": sys.argv[1], "whatsappNumber": nums[0] if len(nums) == 1 else nums}
print(json.dumps(payload, ensure_ascii=False))
PY
)
    rc=0; req_soft POST "/agent-whitelist-whatsapp" "$PAYLOAD" || rc=$?
    [ "$rc" -eq 0 ] || propaga_erro "$AGENT_ID"
    FORMATTER='
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, list):
    print(json.dumps(d, ensure_ascii=False)); raise SystemExit
print("Whitelist do agente: %d número(s)." % len(d))
for e in d:
    if isinstance(e, dict):
        print("  + %s" % e.get("whatsappNumber", ""))
'
    cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
    ;;

  update)
    AGENT_ID="${1:-}"; shift || true
    OLD="${1:-}"; shift || true
    NEW="${1:-}"; shift || true
    [ -n "$AGENT_ID" ] && [ -n "$OLD" ] && [ -n "$NEW" ] || { usage >&2; cv_die "update exige <agent-id> <numero-antigo> <numero-novo>"; }
    PAYLOAD=$(python3 - "$OLD" "$NEW" <<'PY'
import json, sys
print(json.dumps({"oldWhatsappNumber": sys.argv[1], "newWhatsappNumber": sys.argv[2]}, ensure_ascii=False))
PY
)
    cv_confirm "Trocar o número ${OLD} por ${NEW} na whitelist do agente ${AGENT_ID}?"
    rc=0; req_soft PATCH "/agent-whitelist-whatsapp/${AGENT_ID}" "$PAYLOAD" || rc=$?
    [ "$rc" -eq 0 ] || propaga_erro "$AGENT_ID"
    FORMATTER='
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    print("Número atualizado na whitelist: %s" % d.get("whatsappNumber", ""))
else:
    print(json.dumps(d, ensure_ascii=False))
'
    cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
    ;;

  remove)
    AGENT_ID="${1:-}"; shift || true
    NUM="${1:-}"; shift || true
    [ -n "$AGENT_ID" ] && [ -n "$NUM" ] || { usage >&2; cv_die "remove exige <agent-id> <numero>"; }
    PAYLOAD=$(python3 - "$NUM" <<'PY'
import json, sys
print(json.dumps({"whatsappNumber": sys.argv[1]}, ensure_ascii=False))
PY
)
    cv_confirm "Remover o número ${NUM} da whitelist do agente ${AGENT_ID}?"
    rc=0; req_soft DELETE "/agent-whitelist-whatsapp/${AGENT_ID}" "$PAYLOAD" || rc=$?
    [ "$rc" -eq 0 ] || propaga_erro "$AGENT_ID"
    FORMATTER='
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and d.get("message"):
    print(d["message"])
else:
    print("Número removido da whitelist.")
'
    cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
    ;;
esac
