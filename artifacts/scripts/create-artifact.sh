#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — create-artifact
#
# Cria um artefato (POST /artifacts). O contrato exige `name` e `categoryId`
# (CreateArtifactPayload); `description`, `price`, `externalUrl`, `customJson`
# e `isActive` são opcionais.
#
# Uso:
#   create-artifact.sh [api-key] --name <nome> --category <id> [opções]
#
# Opções:
#   --name <nome>          nome do artefato (obrigatório)
#   --category <id>        id da categoria (obrigatório)
#   --description <texto>  descrição
#   --price <numero>       preço (number)
#   --external-url <url>   URL externa
#   --active <bool>        true|false (padrão da API: ativo)
#   --json '<objeto>'      campos extras em JSON (sobrepõe os demais)
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
create-artifact.sh — cria um artefato no Chatvolt (POST /artifacts)

Uso:
  create-artifact.sh [api-key] --name <nome> --category <id> [opções]

Opções:
  --name <nome>          nome do artefato (obrigatório)
  --category <id>        id da categoria (categoryId, obrigatório)
  --description <texto>  descrição do artefato
  --price <numero>       preço (campo number do contrato)
  --external-url <url>   URL externa do conteúdo
  --active <bool>        true|false (isActive)
  --json '<objeto>'      campos extras (customJson, isActive, ...) em JSON
  -h, --help             mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

NAME=""
CATEGORY=""
DESCRIPTION=""
PRICE=""
EXTERNAL_URL=""
ACTIVE=""
EXTRA=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)         NAME="${2:?--name exige um valor}"; shift 2 ;;
    --category)     CATEGORY="${2:?--category exige um id}"; shift 2 ;;
    --description)  DESCRIPTION="${2:?--description exige um valor}"; shift 2 ;;
    --price)        PRICE="${2:?--price exige um número}"; shift 2 ;;
    --external-url) EXTERNAL_URL="${2:?--external-url exige uma URL}"; shift 2 ;;
    --active)       ACTIVE="${2:?--active exige true ou false}"; shift 2 ;;
    --json)         EXTRA="${2:?--json exige um objeto JSON}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) cv_die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

[ -n "$NAME" ] || { usage >&2; cv_die "--name é obrigatório"; }
[ -n "$CATEGORY" ] || { usage >&2; cv_die "--category é obrigatório (CreateArtifactPayload exige categoryId)"; }
if [ -n "$ACTIVE" ]; then
  case "$ACTIVE" in true|false|TRUE|FALSE|1|0|sim|nao) ;; *) cv_die "--active aceita true ou false" ;; esac
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

# Payload montado por argv (nunca por interpolação em código Python).
if ! PAYLOAD=$(python3 - "$NAME" "$CATEGORY" "$DESCRIPTION" "$PRICE" "$EXTERNAL_URL" "$ACTIVE" "$EXTRA" <<'PY'
import json, sys
name, category, description, price, external_url, active, extra = sys.argv[1:8]
p = {"name": name, "categoryId": category}
if description:
    p["description"] = description
if price != "":
    try:
        p["price"] = float(price)
    except ValueError:
        print(f"ERRO: --price deve ser numérico (recebi: {price})", file=sys.stderr)
        raise SystemExit(1)
if external_url:
    p["externalUrl"] = external_url
if active != "":
    p["isActive"] = active.lower() in ("true", "1", "sim")
if extra:
    try:
        ex = json.loads(extra)
    except Exception:
        print(f"ERRO: --json não é JSON válido: {extra}", file=sys.stderr)
        raise SystemExit(1)
    if not isinstance(ex, dict):
        print("ERRO: --json deve ser um objeto JSON", file=sys.stderr)
        raise SystemExit(1)
    p.update(ex)
print(json.dumps(p, ensure_ascii=False))
PY
); then exit 1; fi

cv_request POST "/artifacts" "$PAYLOAD"
RESP=$(cv_unwrap "$CV_RESP")

read -r -d '' FORMATTER <<'PY' || true
import json, sys
a = json.load(sys.stdin)
if not isinstance(a, dict):
    print(json.dumps(a, ensure_ascii=False, indent=2))
    raise SystemExit
print(f"Artefato criado: {a.get('name','')}")
print(f"ID:        {a.get('id','')}")
print(f"Categoria: {a.get('categoryId','')}")
print(f"Ativo:     {'sim' if a.get('isActive') else 'nao'}")
PY

cv_emit "$RESP" "$FORMATTER"
