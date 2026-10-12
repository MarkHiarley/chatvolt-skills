#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — update-artifact
#
# Atualiza um artefato (PUT /artifacts/{id}). O PUT SUBSTITUI os campos:
# por isso o script lê o artefato atual (GET /artifacts/{id}), mescla só os
# campos informados e reenvia o conjunto completo de campos editáveis —
# assim uma mudança parcial não apaga descrição, preço ou categoria.
#
# Uso:
#   update-artifact.sh [api-key] <artifact-id> [opções]
#
# Opções:
#   --name <nome>          novo nome
#   --description <texto>  nova descrição
#   --category <id>        novo categoryId
#   --price <numero>       novo preço
#   --external-url <url>   nova URL externa
#   --active <bool>        true|false (isActive)
#   --json '<objeto>'      campos extras em JSON (sobrepõe os demais)
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_YES=1           pula a confirmação (operação de escrita)
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
update-artifact.sh — atualiza um artefato do Chatvolt (PUT /artifacts/{id})

Uso:
  update-artifact.sh [api-key] <artifact-id> [opções]

Argumentos:
  <artifact-id>   id do artefato a atualizar

Opções:
  --name <nome>          novo nome
  --description <texto>  nova descrição
  --category <id>        novo categoryId
  --price <numero>       novo preço
  --external-url <url>   nova URL externa
  --active <bool>        true|false (isActive)
  --json '<objeto>'      campos extras (ex.: customJson) em JSON
  -h, --help             mostra esta ajuda

O PUT substitui o artefato: o script lê o estado atual e reenvia os campos
não alterados, então só os campos editáveis são sobrescritos.

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_YES=1            pula a confirmação
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

ART_ID=""
NAME=""
DESCRIPTION=""
CATEGORY=""
PRICE=""
EXTERNAL_URL=""
ACTIVE=""
EXTRA=""
SEEN_NAME=0; SEEN_DESC=0; SEEN_CAT=0; SEEN_PRICE=0; SEEN_URL=0; SEEN_ACTIVE=0; SEEN_EXTRA=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)         NAME="${2:?--name exige um valor}"; SEEN_NAME=1; shift 2 ;;
    --description)  DESCRIPTION="${2:?--description exige um valor}"; SEEN_DESC=1; shift 2 ;;
    --category)     CATEGORY="${2:?--category exige um id}"; SEEN_CAT=1; shift 2 ;;
    --price)        PRICE="${2:?--price exige um número}"; SEEN_PRICE=1; shift 2 ;;
    --external-url) EXTERNAL_URL="${2:?--external-url exige uma URL}"; SEEN_URL=1; shift 2 ;;
    --active)       ACTIVE="${2:?--active exige true ou false}"; SEEN_ACTIVE=1; shift 2 ;;
    --json)         EXTRA="${2:?--json exige um objeto JSON}"; SEEN_EXTRA=1; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    -*)             cv_die "opção desconhecida: $1 (use --help)" ;;
    *)              if [ -z "$ART_ID" ]; then ART_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$ART_ID" ] || { usage >&2; cv_die "informe o id do artefato"; }
if [ "$SEEN_NAME$SEEN_DESC$SEEN_CAT$SEEN_PRICE$SEEN_URL$SEEN_ACTIVE$SEEN_EXTRA" = "0000000" ]; then
  cv_die "informe ao menos um campo para atualizar (--name, --description, --category, --price, --external-url, --active ou --json)"
fi
if [ "$SEEN_ACTIVE" = "1" ]; then
  case "$ACTIVE" in true|false|TRUE|FALSE|1|0|sim|nao) ;; *) cv_die "--active aceita true ou false" ;; esac
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

# 1) Estado atual (somente leitura) — o PUT substitui o artefato inteiro.
cv_get "/artifacts/${ART_ID}"
CURRENT=$(cv_unwrap "$CV_RESP")

if [ -z "$CURRENT" ] || [ "$CURRENT" = "null" ]; then cv_die "artefato não encontrado: ${ART_ID}"; fi

CUR_NAME=$(printf '%s' "$CURRENT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("name") or "")')
cv_info "artefato atual: ${CUR_NAME} (${ART_ID})"

if ! PAYLOAD=$(python3 - "$CURRENT" "$NAME" "$DESCRIPTION" "$CATEGORY" "$PRICE" "$EXTERNAL_URL" "$ACTIVE" "$EXTRA" \
                             "$SEEN_NAME" "$SEEN_DESC" "$SEEN_CAT" "$SEEN_PRICE" "$SEEN_URL" "$SEEN_ACTIVE" "$SEEN_EXTRA" <<'PY'
import json, sys
(cur_raw, name, description, category, price, external_url, active, extra,
 sn, sd, sc, sp, su, sa, se) = sys.argv[1:16]
cur = json.loads(cur_raw)
# Campos editáveis de UpdateArtifactPayload.
p = {}
for key in ("name", "description", "price", "externalUrl", "customJson", "categoryId", "isActive"):
    if key in cur and cur[key] is not None:
        p[key] = cur[key]
if sn == "1":
    p["name"] = name
if sd == "1":
    p["description"] = description
if sc == "1":
    p["categoryId"] = category
if sp == "1":
    try:
        p["price"] = float(price)
    except ValueError:
        print(f"ERRO: --price deve ser numérico (recebi: {price})", file=sys.stderr)
        raise SystemExit(1)
if su == "1":
    p["externalUrl"] = external_url
if sa == "1":
    p["isActive"] = active.lower() in ("true", "1", "sim")
if se == "1":
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

cv_info "campos enviados no PUT: $(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; print(", ".join(sorted(json.load(sys.stdin).keys())))')"
cv_confirm "Aplicar PUT em /artifacts/${ART_ID}?"

cv_request PUT "/artifacts/${ART_ID}" "$PAYLOAD"
RESP=$(cv_unwrap "$CV_RESP")

read -r -d '' FORMATTER <<'PY' || true
import json, sys
a = json.load(sys.stdin)
if not isinstance(a, dict):
    print(json.dumps(a, ensure_ascii=False, indent=2))
    raise SystemExit
print(f"Artefato atualizado: {a.get('name','')}")
print(f"ID:        {a.get('id','')}")
print(f"Categoria: {a.get('categoryId','')}")
print(f"Ativo:     {'sim' if a.get('isActive') else 'nao'}")
print(f"Atualizado em: {a.get('updatedAt') or '-'}")
PY

cv_emit "$RESP" "$FORMATTER"
