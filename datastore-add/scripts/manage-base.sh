#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Menu interativo para manter uma base de conhecimento.
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./manage-base.sh <api-key> [<datastore-id>]

Menu interativo para criar/consultar/manter bases de conhecimento.
Sem <datastore-id>, o script lista as bases e pede para escolher uma.

Ações do menu:
  1  listar bases de conhecimento
  2  detalhar a base atual (metadados + fontes)
  3  listar as fontes da base
  4  adicionar uma fonte (texto, arquivo, PDF, pergunta/resposta ou URL)
  5  consultar a base (busca semântica)
  6  verificar a indexação de uma fonte
  7  conectar a base a um agente (tool datastore)
  8  deletar uma fonte
  9  deletar a base (e todas as fontes)
  0  sair

O menu delega para os scripts desta skill (add-source.sh, query-base.sh, ...).
As operações destrutivas (deletar fonte/base, upsert) pedem confirmação.

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DS_ID="${POS[1]:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"

ask() {
  local prompt="$1" __var="$2"
  printf '%s' "$prompt" >&2
  read -r "$__var" || { echo >&2; exit 130; }
}

if [ -z "$DS_ID" ]; then
  "$HERE/list-datastores.sh" "$API_KEY" --limit 20
  ask "Digite o id da base de conhecimento: " DS_ID
fi
[ -n "$DS_ID" ] || cv_die "nenhuma base informada"

cv_get "/datastores/${DS_ID}?limit=1"
DS_NAME=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("name") or "")')

while :; do
  echo >&2
  echo "=== Base ${DS_NAME} (${DS_ID}) ===" >&2
  cat >&2 <<'EOF'
  1) listar bases            5) consultar a base           9) deletar a base
  2) detalhar a base         6) verificar indexação de fonte
  3) listar fontes           7) conectar a um agente
  4) adicionar fonte         8) deletar uma fonte           0) sair
EOF
  ask "Ação: " ACTION
  case "$ACTION" in
    1) "$HERE/list-datastores.sh" "$API_KEY" --all ;;
    2) "$HERE/get-datastore.sh" "$API_KEY" "$DS_ID" --limit 50 ;;
    3) "$HERE/list-sources.sh" "$API_KEY" "$DS_ID" --all ;;
    4)
      cat >&2 <<'EOF'
Tipo de conteúdo:
  t) texto digitado agora        f) arquivo local (texto ou PDF)
  q) pergunta::resposta          u) URL (web_page)
  s) URL de site (web_site)      v) voltar
EOF
      ask "Tipo: " KIND
      case "$KIND" in
        t)
          ask "Cole o texto (uma linha): " TXT
          ask "Nome da fonte (enter para derivar do texto): " SNAME
          ask "Etiquetas separadas por vírgula (enter para nenhuma): " STAGS
          set -- "$HERE/add-source.sh" "$API_KEY" "$DS_ID" --text "$TXT"
          [ -n "$SNAME" ] && set -- "$@" --name "$SNAME"
          [ -n "$STAGS" ] && set -- "$@" --tags "$STAGS"
          "$@"
          ;;
        f)
          ask "Caminho do arquivo: " FPATH
          ask "Etiquetas separadas por vírgula (enter para nenhuma): " STAGS
          set -- "$HERE/add-source.sh" "$API_KEY" "$DS_ID" --file "$FPATH"
          [ -n "$STAGS" ] && set -- "$@" --tags "$STAGS"
          "$@"
          ;;
        q)
          ask "Pergunta::Resposta: " QA
          "$HERE/add-source.sh" "$API_KEY" "$DS_ID" --qa "$QA"
          ;;
        u|s)
          ask "URL: " URL
          set -- "$HERE/add-source.sh" "$API_KEY" "$DS_ID" --url "$URL"
          [ "$KIND" = "s" ] && set -- "$@" --site
          "$@"
          ;;
        v) : ;;
        *) cv_warn "opção inválida: $KIND" ;;
      esac
      ;;
    5)
      ask "Pergunta: " Q
      ask "Trechos (enter = 5): " K
      set -- "$HERE/query-base.sh" "$API_KEY" "$DS_ID" "$Q"
      [ -n "$K" ] && set -- "$@" --top-k "$K"
      "$@"
      ;;
    6)
      ask "Id da fonte: " SID
      "$HERE/get-source.sh" "$API_KEY" "$DS_ID" "$SID"
      ;;
    7)
      ask "Id do agente: " AID
      ask "Nome da tool (enter para nenhum): " TNAME
      set -- "$HERE/attach-to-agent.sh" "$API_KEY" "$AID" "$DS_ID"
      [ -n "$TNAME" ] && set -- "$@" --name "$TNAME"
      "$@"
      ;;
    8)
      "$HERE/list-sources.sh" "$API_KEY" "$DS_ID" --all
      ask "Id da fonte a deletar: " SID
      [ -n "$SID" ] && "$HERE/delete-source.sh" "$API_KEY" "$DS_ID" "$SID"
      ;;
    9)
      "$HERE/delete-datastore.sh" "$API_KEY" "$DS_ID"
      exit 0
      ;;
    0|"") exit 0 ;;
    *) cv_warn "opção inválida: $ACTION" ;;
  esac
done
