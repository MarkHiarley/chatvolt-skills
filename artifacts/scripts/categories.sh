#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — categories (categorias de artefatos)
#
# CRUD de /artifact-categories:
#   list                      GET    /artifact-categories      (array na raiz)
#   get <id>                  GET    /artifact-categories/{id}
#   create --name <n>         POST   /artifact-categories      (exige name)
#   update <id> [campos]      PUT    /artifact-categories/{id}
#   delete <id>               DELETE /artifact-categories/{id}  (pede confirmação)
#
# Uso:
#   categories.sh [api-key] <subcomando> [argumentos/opções]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_YES=1           pula a confirmação (PUT/DELETE)
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
categories.sh — categorias de artefatos do Chatvolt (/artifact-categories)

Uso:
  categories.sh [api-key] <subcomando> [argumentos/opções]

Subcomandos:
  list
      Lista as categorias (GET /artifact-categories, array na raiz).

  get <category-id>
      Detalha uma categoria (GET /artifact-categories/{id}).

  create --name <nome> [--description <texto>] [--parent <id>]
      Cria uma categoria (POST /artifact-categories). --name é obrigatório.

  update <category-id> [--name <nome>] [--description <texto>] [--parent <id>] [--active <bool>]
      Atualiza uma categoria (PUT /artifact-categories/{id}).

  delete <category-id>
      Remove uma categoria (DELETE). Pede confirmação; os artefatos dela ficam
      sem categoria.

Opções comuns:
  -h, --help   mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento; sem ela o script
                      tenta o ambiente)
  CV_YES=1            pula a confirmação
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

is_subcmd() {
  case "$1" in list|get|create|update|delete) return 0 ;; *) return 1 ;; esac
}

API_KEY_ARG=""
SUBCMD=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
  if is_subcmd "$1"; then
    SUBCMD="$1"; shift
  else
    API_KEY_ARG="$1"; shift
    if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
      if is_subcmd "$1"; then SUBCMD="$1"; shift; else cv_die "subcomando desconhecido: $1 (use --help)"; fi
    fi
  fi
fi

if [ -z "$SUBCMD" ]; then
  case "${1:-}" in -h|--help) usage; exit 0 ;; esac
  usage >&2
  cv_die "informe o subcomando (use --help)"
fi

# ── argumentos por subcomando ─────────────────────────────────────────────
CAT_ID=""
NAME=""
DESCRIPTION=""
PARENT=""
ACTIVE=""
SEEN_NAME=0; SEEN_DESC=0; SEEN_PARENT=0; SEEN_ACTIVE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)        NAME="${2:?--name exige um valor}"; SEEN_NAME=1; shift 2 ;;
    --description) DESCRIPTION="${2:?--description exige um valor}"; SEEN_DESC=1; shift 2 ;;
    --parent)      PARENT="${2:?--parent exige um id}"; SEEN_PARENT=1; shift 2 ;;
    --active)      ACTIVE="${2:?--active exige true ou false}"; SEEN_ACTIVE=1; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    -*)            cv_die "opção desconhecida: $1 (use --help)" ;;
    *)             if [ -z "$CAT_ID" ]; then CAT_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

read -r -d '' LIST_FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
if not isinstance(d, list) or not d:
    print("Nenhuma categoria encontrada.")
    raise SystemExit
print(f"{'ID':26} {'NOME':34} {'PAI':26} {'ATIVO':6} {'ARTEFATOS':9} DESCRICAO")
for c in d:
    count = (c.get("_count") or {}).get("artifacts")
    if count is None:
        count = "-"
    print(f"{c.get('id',''):26} {str(c.get('name',''))[:34]:34} {str(c.get('parentId') or '-'):26} "
          f"{'sim' if c.get('isActive', True) else 'nao':6} {str(count):9} {str(c.get('description') or '-')[:40]}")
print(f"\nTotal: {len(d)}")
PY

read -r -d '' ONE_FORMATTER <<'PY' || true
import json, sys
c = json.load(sys.stdin)
if isinstance(c, dict) and "data" in c and "error" not in c:
    c = c["data"]
if not isinstance(c, dict) or not c:
    print("Categoria não encontrada.")
    raise SystemExit
print(f"ID:          {c.get('id','')}")
print(f"Nome:        {c.get('name','')}")
print(f"Descrição:   {c.get('description') or '-'}")
print(f"Categoria pai: {c.get('parentId') or '-'}")
print(f"Ativa:       {'sim' if c.get('isActive', True) else 'nao'}")
print(f"Criada em:   {c.get('createdAt') or '-'}")
print(f"Atualizada:  {c.get('updatedAt') or '-'}")
kids = c.get("children")
if kids is not None:
    print(f"Subcategorias: {len(kids)}")
PY

read -r -d '' MSG_FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and d.get("message"):
    print(d["message"])
else:
    print(json.dumps(d, ensure_ascii=False))
PY

build_payload() {
  # $1 = modo: create|update. Monta o objeto a partir dos flags vistos.
  python3 - "$1" "$NAME" "$DESCRIPTION" "$PARENT" "$ACTIVE" \
            "$SEEN_NAME" "$SEEN_DESC" "$SEEN_PARENT" "$SEEN_ACTIVE" <<'PY'
import json, sys
mode, name, description, parent, active, sn, sd, sp, sa = sys.argv[1:10]
p = {}
if sn == "1":
    p["name"] = name
if sd == "1":
    p["description"] = description
if sp == "1":
    p["parentId"] = parent
if sa == "1":
    if active.lower() not in ("true", "false", "1", "0", "sim", "nao"):
        print("ERRO: --active aceita true ou false", file=sys.stderr)
        raise SystemExit(1)
    p["isActive"] = active.lower() in ("true", "1", "sim")
if mode == "create" and not p.get("name"):
    print("ERRO: --name é obrigatório para criar uma categoria", file=sys.stderr)
    raise SystemExit(1)
if mode == "update" and not p:
    print("ERRO: informe ao menos um campo (--name, --description, --parent ou --active)", file=sys.stderr)
    raise SystemExit(1)
print(json.dumps(p, ensure_ascii=False))
PY
}

case "$SUBCMD" in
  list)
    [ -n "$CAT_ID" ] && cv_die "list não aceita argumentos posicionais"
    cv_get "/artifact-categories"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$LIST_FORMATTER"
    ;;

  get)
    [ -n "$CAT_ID" ] || cv_die "get exige o id da categoria"
    cv_get "/artifact-categories/${CAT_ID}"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$ONE_FORMATTER"
    ;;

  create)
    [ -n "$CAT_ID" ] && cv_die "create não aceita argumento posicional (use --name)"
    if ! PAYLOAD=$(build_payload create); then exit 1; fi
    cv_request POST "/artifact-categories" "$PAYLOAD"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$ONE_FORMATTER"
    ;;

  update)
    [ -n "$CAT_ID" ] || cv_die "update exige o id da categoria"
    if ! PAYLOAD=$(build_payload update); then exit 1; fi
    cv_info "campos enviados no PUT: $(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; print(", ".join(sorted(json.load(sys.stdin).keys())))')"
    cv_confirm "Aplicar PUT em /artifact-categories/${CAT_ID}?"
    cv_request PUT "/artifact-categories/${CAT_ID}" "$PAYLOAD"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$ONE_FORMATTER"
    ;;

  delete)
    [ -n "$CAT_ID" ] || cv_die "delete exige o id da categoria"
    cv_get "/artifact-categories/${CAT_ID}"
    CNAME=$(printf '%s' "$(cv_unwrap "$CV_RESP")" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("name") or "" if isinstance(d, dict) else "")')
    cv_info "categoria: ${CNAME:-?} (${CAT_ID})"
    cv_confirm "Deletar a categoria ${CAT_ID}? Os artefatos dela ficam sem categoria."
    cv_request DELETE "/artifact-categories/${CAT_ID}"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$MSG_FORMATTER"
    ;;
esac
