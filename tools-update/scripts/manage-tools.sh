#!/usr/bin/env bash
set -euo pipefail

# chatvolt tools-update — manage-tools.sh
# Menu interativo para listar, ver, criar, atualizar, deletar e exportar as
# tools de um agente. Apenas orquestra os outros scripts desta skill.

usage() {
  cat <<'EOF'
Uso: manage-tools.sh <api-key> <agent-id>

Menu interativo de gerenciamento das tools de um agente:
  1) Listar tools        4) Atualizar tool
  2) Ver uma tool        5) Deletar tool
  3) Criar tool          6) Exportar tools (JSON)
                         7) Sair

Opções:
  -h, --help   Mostra esta ajuda.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CHATVOLT_AGENT_ID   id do agente (alternativa ao 2º argumento)
  CV_API_BASE         sobrescreve a base URL (stub de teste)

Exit codes: 0 ok · 1 erro · 3 quota · 4 rede · 5 servidor · 130 cancelado.

Exemplo:
  manage-tools.sh "$KEY" cmt8mfhzv00h2g9gtypyp54l1
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

source "$(dirname "$0")/_lib.sh"

API_KEY=$(cv_req_key "${1:-}")
AGENT_ID="${2:-${CHATVOLT_AGENT_ID:-}}"
[ -n "$AGENT_ID" ] || cv_die "informe o agent-id como 2º argumento ou exporte CHATVOLT_AGENT_ID"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

AGENT_NAME=$(cv_get "/agents/${AGENT_ID}" && printf '%s' "$CV_RESP" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("N/A"); raise SystemExit
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
print(d.get("name", "N/A") if isinstance(d, dict) else "N/A")
' || echo "N/A")

pause() { read -r -p "Pressione Enter para continuar..." _ || true; }

# Executa um script filho sem abortar o menu em caso de erro (set -e).
run_child() { "$@" || cv_warn "o script retornou erro (exit $?); o menu continua"; }

menu_list() {
  echo
  run_child "${SCRIPT_DIR}/list-tools.sh" "$API_KEY" "$AGENT_ID"
}

menu_view() {
  echo
  read -r -p "Tool ID: " TID || return 0
  [ -n "$TID" ] || { cv_warn "id vazio"; return 0; }
  run_child "${SCRIPT_DIR}/list-tools.sh" "$API_KEY" "$AGENT_ID" --id "$TID" --full
}

menu_create() {
  echo
  echo "Tipos:"
  echo "  1) datastore   2) http   3) http-raw   4) form   5) outro (JSON)"
  read -r -p "Escolha o tipo [1-5]: " OPT || return 0
  case "$OPT" in
    1)
      read -r -p "Datastore ID: " V || return 0
      [ -n "$V" ] && run_child "${SCRIPT_DIR}/create-tool.sh" "$API_KEY" "$AGENT_ID" datastore "$V"
      ;;
    2|3)
      local t="http"; [ "$OPT" = "3" ] && t="http-raw"
      echo "Cole o JSON do corpo (ex.: {\"config\":{\"name\":\"...\",\"description\":\"...\",\"url\":\"...\",\"method\":\"GET\"}})."
      echo "Termine com Ctrl-D:"
      local JSON; JSON=$(cat) || true
      [ -n "$JSON" ] && run_child "${SCRIPT_DIR}/create-tool.sh" "$API_KEY" "$AGENT_ID" "$t" "$JSON"
      ;;
    4)
      read -r -p "Form ID: " V || return 0
      [ -n "$V" ] && run_child "${SCRIPT_DIR}/create-tool.sh" "$API_KEY" "$AGENT_ID" form "$V"
      ;;
    5)
      read -r -p "Tipo (ex.: quick_reply_buttons, request_human...): " T || return 0
      [ -n "$T" ] || return 0
      echo "Cole o JSON do corpo completo. Termine com Ctrl-D:"
      local JSON; JSON=$(cat) || true
      [ -n "$JSON" ] && run_child "${SCRIPT_DIR}/create-tool.sh" "$API_KEY" "$AGENT_ID" "$T" "$JSON"
      ;;
    *) cv_warn "opção inválida" ;;
  esac
}

menu_update() {
  echo
  read -r -p "Tool ID a atualizar: " TID || return 0
  [ -n "$TID" ] || { cv_warn "id vazio"; return 0; }
  echo "Cole o JSON do corpo (o 'type' é injetado do estado atual se ausente). Termine com Ctrl-D:"
  local JSON; JSON=$(cat) || true
  [ -n "$JSON" ] && run_child "${SCRIPT_DIR}/update-tool.sh" "$API_KEY" "$AGENT_ID" "$TID" "$JSON"
}

menu_delete() {
  echo
  read -r -p "Tool ID a deletar: " TID || return 0
  [ -n "$TID" ] || { cv_warn "id vazio"; return 0; }
  run_child "${SCRIPT_DIR}/delete-tool.sh" "$API_KEY" "$AGENT_ID" "$TID"
}

menu_export() {
  echo
  local out="chatvolt-tools-${AGENT_ID}-$(date +%Y%m%d-%H%M%S).json"
  if ! "${SCRIPT_DIR}/list-tools.sh" "$API_KEY" "$AGENT_ID" --full > "$out"; then
    cv_warn "falha ao exportar"; rm -f "$out"; return 0
  fi
  local n
  n=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d) if isinstance(d, list) else 0)' "$out")
  cv_info "✅ ${n} tool(s) exportada(s) para ${out}"
}

echo "══════════════════════════════════════════"
echo "  Chatvolt Tools Manager"
echo "  Agente: ${AGENT_ID} (${AGENT_NAME})"
echo "══════════════════════════════════════════"

while :; do
  echo
  echo "  1) Listar tools         4) Atualizar tool"
  echo "  2) Ver uma tool         5) Deletar tool"
  echo "  3) Criar tool           6) Exportar tools (JSON)"
  echo "                          7) Sair"
  read -r -p "Escolha [1-7]: " OPTION || { echo; break; }
  case "$OPTION" in
    1) menu_list; pause ;;
    2) menu_view; pause ;;
    3) menu_create; pause ;;
    4) menu_update; pause ;;
    5) menu_delete; pause ;;
    6) menu_export; pause ;;
    7|"") echo "Até logo."; break ;;
    *) cv_warn "opção inválida" ;;
  esac
done
