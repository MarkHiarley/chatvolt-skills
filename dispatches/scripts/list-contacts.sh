#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Contatos das listas de disparo (/dispatches/contacts).
# OBS: GET /dispatches/contacts EXIGE contactListId (sem ele a API responde
# 400 {"message":"Query must include 'contactListId'."}).
# Contrato HTTP: SOURCES.md na raiz do repo.

usage() {
  cat <<'EOF'
Uso: ./list-contacts.sh <api-key> [list] --list <contactListId> [--search TEXTO] [--limit N] [--offset N] [--all]
     ./list-contacts.sh <api-key> get <contactId>
     ./list-contacts.sh <api-key> add --list <contactListId> --name NOME --phone TELEFONE [--id CONTACT_ID]
     ./list-contacts.sh <api-key> add --bulk <arquivo.json>
     ./list-contacts.sh <api-key> delete <contactId>

Gerencia os contatos das listas de disparo.
  GET    /dispatches/contacts?contactListId=&offset=&limit=&search=  -> {contacts:[...], count}
         (contactListId é OBRIGATÓRIO; sem ele a API responde 400)
  GET    /dispatches/contacts/<contactId>                            -> contato + contactList
  POST   /dispatches/contacts                                        -> cria (ou atualiza, com "id")
         aceita também um ARRAY de contatos (--bulk)
  DELETE /dispatches/contacts?contactId=<contactId>                  -> {message}

Subcomandos:
  list      lista os contatos de uma lista (padrão quando nenhum subcomando é informado)
  get       mostra um contato pelo id
  add       cria/atualiza contato(s) — um por vez ou em lote (--bulk)
  delete    apaga um contato (com confirmação; busca os dados antes)

Opções:
  --list ID       id da lista de contatos (obrigatório em list/add)
  --contact ID    id do contato (equivalente ao posicional em get/delete)
  --name NOME     nome do contato (add)
  --phone TEL     telefone do contato em formato internacional (add)
  --id ID         id de contato existente para ATUALIZAR (add; upsert)
  --bulk ARQUIVO  envia um array JSON de contatos de uma vez (add)
  --search T      filtra por nome/telefone (list)
  --limit N       itens por página (padrão 100)
  --offset N      deslocamento inicial (padrão 0)
  --all           pagina automaticamente até o fim (list)
  -h, --help      mostra esta ajuda

Exemplos:
  ./list-contacts.sh "$CHATVOLT_API_KEY" --list 30eead17-5b26-4b8d-a82b-e51dff8740f0 --limit 10
  ./list-contacts.sh "$CHATVOLT_API_KEY" get 3d1bd9dd-f1a8-4b0f-ad1d-da905ddbb2d9
  ./list-contacts.sh "$CHATVOLT_API_KEY" add --list "$LIST" --name "Fulano" --phone 5511900000000
  ./list-contacts.sh "$CHATVOLT_API_KEY" add --bulk contatos.json
  CV_YES=1 ./list-contacts.sh "$CHATVOLT_API_KEY" delete 3d1bd9dd-...

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

SUB=""
LIST_ID=""; CONTACT_ID=""; NAME=""; PHONE=""; BULK=""
SEARCH=""; LIMIT=100; OFFSET=0; ALL=0
POS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list) [ "$#" -ge 2 ] || { echo "ERRO: --list exige um valor" >&2; exit 1; }; LIST_ID="$2"; shift 2 ;;
    --contact) [ "$#" -ge 2 ] || { echo "ERRO: --contact exige um valor" >&2; exit 1; }; CONTACT_ID="$2"; shift 2 ;;
    --name) [ "$#" -ge 2 ] || { echo "ERRO: --name exige um valor" >&2; exit 1; }; NAME="$2"; shift 2 ;;
    --phone) [ "$#" -ge 2 ] || { echo "ERRO: --phone exige um valor" >&2; exit 1; }; PHONE="$2"; shift 2 ;;
    --id) [ "$#" -ge 2 ] || { echo "ERRO: --id exige um valor" >&2; exit 1; }; CONTACT_ID="$2"; shift 2 ;;
    --bulk) [ "$#" -ge 2 ] || { echo "ERRO: --bulk exige um arquivo" >&2; exit 1; }; BULK="$2"; shift 2 ;;
    --search) [ "$#" -ge 2 ] || { echo "ERRO: --search exige um valor" >&2; exit 1; }; SEARCH="$2"; shift 2 ;;
    --limit) [ "$#" -ge 2 ] || { echo "ERRO: --limit exige um valor" >&2; exit 1; }; LIMIT="$2"; shift 2 ;;
    --offset) [ "$#" -ge 2 ] || { echo "ERRO: --offset exige um valor" >&2; exit 1; }; OFFSET="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
SUBCMD="${POS[1]:-list}"
case "$SUBCMD" in
  list|get|add|delete) ;;
  *) cv_die "subcomando desconhecido: ${SUBCMD} (use list, get, add ou delete)" ;;
esac
[ -n "$CONTACT_ID" ] || CONTACT_ID="${POS[2]:-}"

case "$LIMIT" in ''|*[!0-9]*) cv_die "--limit deve ser um número inteiro" ;; esac
case "$OFFSET" in ''|*[!0-9]*) cv_die "--offset deve ser um número inteiro" ;; esac
[ "$LIMIT" -gt 0 ] || cv_die "--limit deve ser maior que zero"

case "$SUBCMD" in
  list)
    [ -n "$LIST_ID" ] || cv_die "--list é obrigatório: GET /dispatches/contacts exige contactListId"
    TMPD=$(mktemp -d)
    trap 'rm -rf "$TMPD"' EXIT
    PAGE=0
    CUR="$OFFSET"
    while :; do
      Q=$(python3 - "$LIST_ID" "$CUR" "$LIMIT" "$SEARCH" <<'PY'
import sys, urllib.parse
list_id, offset, limit, search = sys.argv[1:5]
p = {"contactListId": list_id, "offset": offset, "limit": limit}
if search:
    p["search"] = search
print(urllib.parse.urlencode(p))
PY
)
      cv_get "/dispatches/contacts?${Q}"
      printf '%s' "$CV_RESP" > "${TMPD}/${PAGE}.json"
      N=$(python3 - "${TMPD}/${PAGE}.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
items = d.get("contacts") if isinstance(d, dict) else (d if isinstance(d, list) else [])
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
        items.extend(d.get("contacts") or [])
        count = int(d.get("count") or count)
    elif isinstance(d, list):
        items.extend(d)
print(json.dumps({"contacts": items, "count": count or len(items)}, ensure_ascii=False))
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
        items.extend(d.get("contacts") or [])
    elif isinstance(d, list):
        items.extend(d)

def cut(v, n):
    s = "" if v is None else str(v)
    return s if len(s) <= n else s[:n - 1] + "…"

if not items:
    print("Nenhum contato encontrado nesta lista.")
    raise SystemExit

print(f"{'ID':<38} {'NOME':<32} {'TELEFONE':<20}  CRIADO")
print("-" * 118)
for c in items:
    print(f"{cut(c.get('id'), 37):<38} {cut(c.get('name'), 31):<32} "
          f"{cut(c.get('phoneNumber'), 19):<20}  {cut(c.get('createdAt'), 24)}")
print()
print(f"{len(items)} contato(s).")
PY
    fi
    ;;

  get)
    [ -n "$CONTACT_ID" ] || cv_die "informe o id do contato: list-contacts.sh <api-key> get <contactId>"
    REQ_PATH=$(python3 -c 'import sys, urllib.parse; print("/dispatches/contacts/" + urllib.parse.quote(sys.argv[1], safe=""))' "$CONTACT_ID")
    cv_get "$REQ_PATH"
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
if not isinstance(d, dict):
    print(json.dumps(d, ensure_ascii=False))
    raise SystemExit
print("Contato de disparo:")
for label, key in (("id", "id"), ("nome", "name"), ("telefone", "phoneNumber"),
                   ("lista", "contactListId"), ("criado em", "createdAt"), ("atualizado em", "updatedAt")):
    print("  " + (label + ":").ljust(15) + " " + str(d.get(key)))
lst = d.get("contactList")
if isinstance(lst, dict):
    print("  lista (nome):   " + str(lst.get("name")))
PY
    fi
    ;;

  add)
    if [ -n "$BULK" ]; then
      [ -f "$BULK" ] || cv_die "arquivo não encontrado: ${BULK}"
      if ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert isinstance(d, list) and d' "$BULK" 2>/dev/null; then
        cv_die "--bulk exige um arquivo JSON com um ARRAY de contatos (ex.: [{\"name\":\"Fulano\",\"phoneNumber\":\"5511900000000\"}])"
      fi
      BODY=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), ensure_ascii=False))' "$BULK")
      cv_warn "Enviando lote de contatos (POST /dispatches/contacts com array)."
    else
      [ -n "$LIST_ID" ] || cv_die "--list é obrigatório em add (contactListId do contato)"
      [ -n "$NAME" ] || cv_die "--name é obrigatório em add"
      [ -n "$PHONE" ] || cv_die "--phone é obrigatório em add"
      BODY=$(python3 - "$LIST_ID" "$NAME" "$PHONE" "$CONTACT_ID" <<'PY'
import json, sys
list_id, name, phone, cid = sys.argv[1:5]
body = {"name": name, "phoneNumber": phone, "contactListId": list_id}
if cid:
    body["id"] = cid
print(json.dumps(body, ensure_ascii=False))
PY
)
    fi
    cv_request POST "/dispatches/contacts" "$BODY"
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
print("Contato(s) salvos:")
if isinstance(d, dict):
    for label, key in (("id", "id"), ("nome", "name"), ("telefone", "phoneNumber"), ("lista", "contactListId")):
        print("  " + (label + ":").ljust(11) + " " + str(d.get(key)))
elif isinstance(d, list):
    print("  " + str(len(d)) + " contato(s) no lote")
    for c in d[:10]:
        print("  - " + str(c.get("name")) + " / " + str(c.get("phoneNumber")) + " (" + str(c.get("id")) + ")")
else:
    print(json.dumps(d, ensure_ascii=False))
PY
    fi
    ;;

  delete)
    [ -n "$CONTACT_ID" ] || cv_die "informe o id do contato: list-contacts.sh <api-key> delete <contactId>"
    REQ_PATH=$(python3 -c 'import sys, urllib.parse; print("/dispatches/contacts/" + urllib.parse.quote(sys.argv[1], safe=""))' "$CONTACT_ID")
    cv_get "$REQ_PATH"
    if [ "$CV_JSON" != "1" ]; then
      printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
print("Contato a deletar:")
for label, key in (("id", "id"), ("nome", "name"), ("telefone", "phoneNumber"), ("lista", "contactListId")):
    print("  " + (label + ":").ljust(11) + " " + str(d.get(key)))
'
    fi
    cv_confirm "Deletar o contato ${CONTACT_ID} da lista de disparo"
    Q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.urlencode({"contactId": sys.argv[1]}))' "$CONTACT_ID")
    cv_request DELETE "/dispatches/contacts?${Q}"
    if [ "$CV_JSON" = "1" ]; then
      if [ -z "$CV_RESP" ]; then printf '%s\n' '{"success":true}'; else cv_emit "$CV_RESP"; fi
    else
      TMPF=$(mktemp); trap 'rm -f "$TMPF"' EXIT
      printf '%s' "$CV_RESP" > "$TMPF"
      python3 - "$TMPF" "$CONTACT_ID" <<'PY'
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
print(msg or f"Contato {sys.argv[2]} deletado.")
PY
    fi
    ;;
esac
