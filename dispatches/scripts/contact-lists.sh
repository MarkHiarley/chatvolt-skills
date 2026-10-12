#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Listas de contatos de disparo (/dispatches/contacts/lists).
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./contact-lists.sh <api-key> list [--search TEXTO] [--limit N] [--offset N] [--all]
     ./contact-lists.sh <api-key> create --name NOME
     ./contact-lists.sh <api-key> update <list-id> --name NOME [--post]
     ./contact-lists.sh <api-key> delete <list-id>

Gerencia as listas de contatos usadas pelos disparos.
  GET    /dispatches/contacts/lists?offset=&limit=&search=   -> {lists:[...], count}
  POST   /dispatches/contacts/lists                          -> cria; com "id" no corpo, ATUALIZA (upsert)
  PUT    /dispatches/contacts/lists                          -> atualiza (rota dedicada; padrão do subcomando update)
  DELETE /dispatches/contacts/lists?id=<list-id>             -> {message}

Subcomandos:
  list      lista as listas (padrão quando nenhum subcomando é informado)
  create    cria uma lista nova (--name)
  update    atualiza o nome de uma lista com PUT (rota dedicada); use --post
            para fazer o upsert pelo POST (rota "cria ou atualiza")
  delete    apaga a lista e todos os dados associados (com confirmação)

Opções:
  --name NOME   nome da lista (create/update)
  --search T    filtra por nome (list)
  --limit N     itens por página (padrão 100)
  --offset N    deslocamento inicial (padrão 0)
  --all         pagina automaticamente até o fim (list)
  --post        no update, usa POST /dispatches/contacts/lists (upsert) em vez do PUT
  -h, --help    mostra esta ajuda

Exemplos:
  ./contact-lists.sh "$CHATVOLT_API_KEY" list --limit 10
  ./contact-lists.sh "$CHATVOLT_API_KEY" create --name "Leads Outubro"
  ./contact-lists.sh "$CHATVOLT_API_KEY" update 30eead17-... --name "Leads Outubro 2026"
  ./contact-lists.sh "$CHATVOLT_API_KEY" update 30eead17-... --name "Leads 2026" --post
  CV_YES=1 ./contact-lists.sh "$CHATVOLT_API_KEY" delete 30eead17-...

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

SUB=""
NAME=""; SEARCH=""; LIMIT=100; OFFSET=0; ALL=0; USE_POST=0
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --name) [ "$#" -ge 2 ] || { echo "ERRO: --name exige um valor" >&2; exit 1; }; NAME="$2"; shift 2 ;;
    --search) [ "$#" -ge 2 ] || { echo "ERRO: --search exige um valor" >&2; exit 1; }; SEARCH="$2"; shift 2 ;;
    --limit) [ "$#" -ge 2 ] || { echo "ERRO: --limit exige um valor" >&2; exit 1; }; LIMIT="$2"; shift 2 ;;
    --offset) [ "$#" -ge 2 ] || { echo "ERRO: --offset exige um valor" >&2; exit 1; }; OFFSET="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --post) USE_POST=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
SUBCMD="${POS[1]:-list}"
case "$SUBCMD" in
  list|create|update|delete) ;;
  *) cv_die "subcomando desconhecido: ${SUBCMD} (use list, create, update ou delete)" ;;
esac
LIST_ID="${POS[2]:-}"

case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um número inteiro" ;; esac
case "$OFFSET" in ''|*[!0-9]*) cv_die "--offset deve ser um número inteiro" ;; esac
[ "$LIMIT" -gt 0 ] || cv_die "--limit deve ser maior que zero"

case "$SUBCMD" in
  list)
    TMPD=$(mktemp -d)
    trap 'rm -rf "$TMPD"' EXIT
    PAGE=0
    CUR="$OFFSET"
    while :; do
      Q=$(python3 - "$CUR" "$LIMIT" "$SEARCH" <<'PY'
import sys, urllib.parse
offset, limit, search = sys.argv[1:4]
p = {"offset": offset, "limit": limit}
if search:
    p["search"] = search
print(urllib.parse.urlencode(p))
PY
)
      cv_get "/dispatches/contacts/lists?${Q}"
      printf '%s' "$CV_RESP" > "${TMPD}/${PAGE}.json"
      N=$(python3 - "${TMPD}/${PAGE}.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
items = d.get("lists") if isinstance(d, dict) else (d if isinstance(d, list) else [])
print(len(items or []))
PY
)
      [ "$ALL" = "1" ] || break
      [ "$N" -gt 0 ] || break
      [ "$N" -lt "$LIMIT" ] && break
      PAGE=$((PAGE + 1))
      CUR=$((CUR + N))
    done

    if [ "$CV_JSON" = "1" ]; then
      python3 - "$TMPD" <<'PY'
import glob, json, os, sys

files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items, count = [], 0
for f in files:
    d = json.load(open(f, encoding="utf-8"))
    if isinstance(d, dict):
        items.extend(d.get("lists") or [])
        count = int(d.get("count") or count)
    elif isinstance(d, list):
        items.extend(d)
print(json.dumps({"lists": items, "count": count or len(items)}, ensure_ascii=False))
PY
    else
      python3 - "$TMPD" <<'PY'
import glob, json, os, sys

files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")),
               key=lambda p: int(os.path.basename(p)[:-5]))
items = []
for f in files:
    d = json.load(open(f, encoding="utf-8"))
    if isinstance(d, dict):
        items.extend(d.get("lists") or [])
    elif isinstance(d, list):
        items.extend(d)

def cut(v, n):
    s = "" if v is None else str(v)
    return s if len(s) <= n else s[:n - 1] + "…"

if not items:
    print("Nenhuma lista de contatos de disparo encontrada.")
    raise SystemExit

print(f"{'ID':<38} {'NOME':<30} {'CONTATOS':>8}  CRIADA")
print("-" * 100)
for l in items:
    print(f"{cut(l.get('id'), 37):<38} {cut(l.get('name'), 29):<30} "
          f"{str(l.get('contactsCount', '?')):>8}  {cut(l.get('createdAt'), 24)}")
print()
print(f"{len(items)} lista(s) de contatos.")
PY
    fi
    ;;

  create)
    [ -n "$NAME" ] || cv_die "--name é obrigatório em create"
    BODY=$(python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1]}, ensure_ascii=False))' "$NAME")
    cv_request POST "/dispatches/contacts/lists" "$BODY"
    if [ "$CV_JSON" = "1" ]; then
      cv_emit "$CV_RESP"
    else
      TMPF=$(mktemp); trap 'rm -f "$TMPF"' EXIT
      printf '%s' "$CV_RESP" > "$TMPF"
      python3 - "$TMPF" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
print("Lista de contatos criada:")
if isinstance(d, dict):
    print("  id:   " + str(d.get("id")))
    print("  nome: " + str(d.get("name")))
else:
    print(json.dumps(d, ensure_ascii=False))
PY
    fi
    ;;

  update)
    [ -n "$LIST_ID" ] || cv_die "informe o id da lista: contact-lists.sh <api-key> update <list-id> --name NOME"
    [ -n "$NAME" ] || cv_die "--name é obrigatório em update"
    BODY=$(python3 -c 'import json,sys; print(json.dumps({"id": sys.argv[1], "name": sys.argv[2]}, ensure_ascii=False))' "$LIST_ID" "$NAME")
    if [ "$USE_POST" = "1" ]; then
      cv_confirm "Atualizar (upsert POST) a lista ${LIST_ID} para o nome \"${NAME}\"?"
      cv_request POST "/dispatches/contacts/lists" "$BODY"
    else
      cv_confirm "Atualizar (PUT) a lista ${LIST_ID} para o nome \"${NAME}\"?"
      cv_request PUT "/dispatches/contacts/lists" "$BODY"
    fi
    if [ "$CV_JSON" = "1" ]; then
      cv_emit "$CV_RESP"
    else
      TMPF=$(mktemp); trap 'rm -f "$TMPF"' EXIT
      printf '%s' "$CV_RESP" > "$TMPF"
      python3 - "$TMPF" "$LIST_ID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
print("Lista de contatos atualizada:")
if isinstance(d, dict):
    print("  id:   " + str(d.get("id") or sys.argv[2]))
    print("  nome: " + str(d.get("name")))
else:
    print(json.dumps(d, ensure_ascii=False))
PY
    fi
    ;;

  delete)
    [ -n "$LIST_ID" ] || cv_die "informe o id da lista: contact-lists.sh <api-key> delete <list-id>"
    cv_confirm "Deletar a lista de contatos ${LIST_ID}? Todos os contatos da lista serão removidos"
    Q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.urlencode({"id": sys.argv[1]}))' "$LIST_ID")
    cv_request DELETE "/dispatches/contacts/lists?${Q}"
    if [ "$CV_JSON" = "1" ]; then
      if [ -z "$CV_RESP" ]; then printf '%s\n' '{"success":true}'; else cv_emit "$CV_RESP"; fi
    else
      TMPF=$(mktemp); trap 'rm -f "$TMPF"' EXIT
      printf '%s' "$CV_RESP" > "$TMPF"
      python3 - "$TMPF" "$LIST_ID" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read().strip()
msg = ""
if raw:
    try:
        d = json.loads(raw)
        if isinstance(d, dict):
            msg = d.get("message") or ""
    except Exception:
        msg = raw
print(msg or f"Lista de contatos {sys.argv[2]} deletada.")
PY
    fi
    ;;
esac
