#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — get-artifact
#
# Detalha um artefato (GET /artifacts/{id}) e, opcionalmente, lista as mídias
# vinculadas (GET /artifacts/media?artifact_id=...). Somente leitura.
#
# Uso:
#   get-artifact.sh [api-key] <artifact-id> [--media]
#
# Opções:
#   --media     também lista as mídias do artefato
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
get-artifact.sh — detalha um artefato do Chatvolt (GET /artifacts/{id})

Uso:
  get-artifact.sh [api-key] <artifact-id> [--media]

Argumentos:
  <artifact-id>   id do artefato (ex.: cmt3e7mgq06qf7w62kbg0kg3k)

Opções:
  --media         também lista as mídias vinculadas (GET /artifacts/media)
  -h, --help      mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

API_KEY_ARG=""
# 1º argumento posicional = api-key (vence o CHATVOLT_API_KEY do ambiente).
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then API_KEY_ARG="$1"; shift; fi

ART_ID=""
WITH_MEDIA=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --media)   WITH_MEDIA=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$ART_ID" ]; then ART_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

[ -n "$ART_ID" ] || { usage >&2; cv_die "informe o id do artefato"; }

API_KEY=$(cv_req_key "$API_KEY_ARG")

read -r -d '' FORMATTER <<'PY' || true
import json, sys
a = json.load(sys.stdin)
if isinstance(a, dict) and "data" in a and "error" not in a:
    a = a["data"]
if not isinstance(a, dict) or not a:
    print("Artefato não encontrado.")
    raise SystemExit
cat = (a.get("category") or {}).get("name") or a.get("categoryId") or "-"
print(f"ID:           {a.get('id','')}")
print(f"Nome:         {a.get('name','')}")
print(f"Descrição:    {a.get('description') or '-'}")
print(f"Categoria:    {cat}")
print(f"Preço:        {a.get('price') if a.get('price') is not None else '-'}")
print(f"URL externa:  {a.get('externalUrl') or '-'}")
print(f"Ativo:        {'sim' if a.get('isActive') else 'nao'}")
print(f"Criado em:    {a.get('createdAt') or '-'}")
print(f"Atualizado:   {a.get('updatedAt') or '-'}")
custom = a.get("customJson")
print(f"customJson:   {json.dumps(custom, ensure_ascii=False) if custom else '-'}")
media = a.get("media")
if media is not None:
    print(f"Mídias:       {len(media)}")
PY

cv_get "/artifacts/${ART_ID}"
ARTIFACT=$(cv_unwrap "$CV_RESP")

if [ "$WITH_MEDIA" = "0" ]; then
  cv_emit "$ARTIFACT" "$FORMATTER"
  exit 0
fi

# GET /artifacts/media exige artifact_id (sem ele a API responde 400).
cv_get "/artifacts/media" --get --data-urlencode "artifact_id=${ART_ID}"
MEDIA=$(cv_unwrap "$CV_RESP")

if [ "$CV_JSON" = "1" ]; then
  python3 - "$ARTIFACT" "$MEDIA" <<'PY'
import json, sys
print(json.dumps({"artifact": json.loads(sys.argv[1]), "media": json.loads(sys.argv[2])},
                 ensure_ascii=False))
PY
  exit 0
fi

read -r -d '' MEDIA_FORMATTER <<'PY' || true
import json, sys
m = json.load(sys.stdin)
print()
if not m:
    print("Mídias: nenhuma.")
    raise SystemExit
print(f"{'ID':26} {'TIPO':10} {'NOME':40} {'ATIVO':6} URL")
for x in m:
    print(f"{x.get('id',''):26} {x.get('mediaType',''):10} {str(x.get('name',''))[:40]:40} "
          f"{'sim' if x.get('isActive') else 'nao':6} {x.get('s3Url','')}")
print(f"\nTotal de mídias: {len(m)}")
PY

printf '%s' "$ARTIFACT" | python3 -c "$FORMATTER"
printf '%s' "$MEDIA" | python3 -c "$MEDIA_FORMATTER"
