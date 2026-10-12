#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — blacklist
#
# Gerencia a blacklist de usuários de um agente:
#   list   [agent-id]                    GET    /agent-blacklist[/{agent-id}]
#   add    <agent-id> <ident> [<ident>…] POST   /agent-blacklist
#   remove <agent-id> <entry-id>         DELETE /agent-blacklist/{agent-id}?id=<entry-id>
#
# DISPONIBILIDADE: medido ao vivo em 2026-10-12, TODAS as rotas /agent-blacklist*
# respondem HTTP 404 neste ambiente (a doc lista, mas o plano/organização não
# expõe o recurso). Os scripts avisam isso de forma explícita em vez de "erro
# genérico". O caminho feliz é validado no stub de teste.
#
# Uso:
#   blacklist.sh [api-key] <list|add|remove> ... [--yes]
#
# Ambiente:
#   CHATVOLT_API_KEY  alternativa à api-key como 1º argumento
#   CV_JSON=1         imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_YES=1          pula a confirmação interativa
#   CV_API_BASE       sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
blacklist.sh — gerencia a blacklist de usuários de um agente

Uso:
  blacklist.sh [api-key] list   [agent-id]
  blacklist.sh [api-key] add    <agent-id> <identificador> [<identificador> ...]
  blacklist.sh [api-key] remove <agent-id> <entry-id>

Comandos:
  list     lista a blacklist da organização (sem agent-id) ou de um agente
  add      adiciona identificador(es) (e-mail, telefone, IP, ...) à blacklist
  remove   remove uma entrada pelo seu entry-id — pede confirmação

Opções:
  --yes      pula a confirmação (remove)
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

# propaga_erro — usa o $rc da última req_soft; explica o 404 e encerra.
propaga_erro() {
  if [ "$rc" -eq 1 ] && [ "$CV_STATUS" = "404" ]; then
    cv_warn "a rota respondeu HTTP 404 (a API devolve a página HTML do dashboard, não um JSON de erro)"
    cv_die "404: as rotas /agent-blacklist* NÃO estão expostas neste plano/organização (medido ao vivo em 2026-10-12). Não é falha do script: a doc lista o endpoint, mas a API pública responde 404 aqui. Use o dashboard ou confirme o plano da organização."
  fi
  [ -n "$REQ_ERR" ] && printf '%s\n' "$REQ_ERR" >&2
  exit "$rc"
}

# Normaliza os argumentos: --yes e -h/--help são reconhecidos em qualquer posição.
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
    -*) cv_die "comando desconhecido: $1 (use list|add|remove, ou --help)" ;;
    *)  CMD="$1"; shift ;;
  esac
fi

case "$CMD" in
  list|add|remove) : ;;
  *) usage >&2; cv_die "informe um comando: list | add | remove" ;;
esac

API_KEY=$(cv_req_key "$API_KEY_ARG")

case "$CMD" in
  list)
    AGENT_ID="${1:-}"; shift || true
    PATH_="/agent-blacklist"
    [ -n "$AGENT_ID" ] && PATH_="/agent-blacklist/${AGENT_ID}"
    rc=0; req_soft GET "$PATH_" || rc=$?
    [ "$rc" -eq 0 ] || propaga_erro
    FORMATTER='
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, list):
    print(json.dumps(d, ensure_ascii=False)); raise SystemExit
print("%-22s %-28s %s" % ("ENTRY-ID", "AGENTE", "USUARIO"))
for e in d:
    if isinstance(e, dict):
        print("%-22s %-28s %s" % (e.get("id", ""), e.get("agentId", ""), e.get("userIdentify", "")))
print("\nTotal: %d" % len(d))
'
    cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
    ;;

  add)
    AGENT_ID="${1:-}"; shift || true
    [ -n "$AGENT_ID" ] || { usage >&2; cv_die "add exige <agent-id> <identificador> [<identificador> ...]"; }
    [ "$#" -ge 1 ] || { usage >&2; cv_die "add exige ao menos um identificador"; }
    PAYLOAD=$(python3 - "$AGENT_ID" "$@" <<'PY'
import json, sys
idents = sys.argv[2:]
payload = {"agentId": sys.argv[1], "userIdentify": idents[0] if len(idents) == 1 else idents}
print(json.dumps(payload, ensure_ascii=False))
PY
)
    rc=0; req_soft POST "/agent-blacklist" "$PAYLOAD" || rc=$?
    [ "$rc" -eq 0 ] || propaga_erro
    FORMATTER='
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, list):
    print(json.dumps(d, ensure_ascii=False)); raise SystemExit
print("Blacklist atualizada: %d entrada(s)." % len(d))
for e in d:
    if isinstance(e, dict):
        print("  + %s (entry-id %s)" % (e.get("userIdentify", ""), e.get("id", "")))
'
    cv_emit "$(cv_unwrap "$CV_RESP")" "$FORMATTER"
    ;;

  remove)
    AGENT_ID="${1:-}"; shift || true
    ENTRY_ID="${1:-}"; shift || true
    [ -n "$AGENT_ID" ] && [ -n "$ENTRY_ID" ] || { usage >&2; cv_die "remove exige <agent-id> <entry-id>"; }
    QID=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$ENTRY_ID")
    cv_confirm "Remover a entrada ${ENTRY_ID} da blacklist do agente ${AGENT_ID}? (a rota responde 404 neste ambiente)"
    rc=0; req_soft DELETE "/agent-blacklist/${AGENT_ID}?id=${QID}" || rc=$?
    [ "$rc" -eq 0 ] || propaga_erro
    if [ -z "$CV_RESP" ]; then
      cv_info "Entrada ${ENTRY_ID} removida (HTTP 204 sem corpo)."
    else
      cv_emit "$(cv_unwrap "$CV_RESP")" 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))'
    fi
    ;;
esac
