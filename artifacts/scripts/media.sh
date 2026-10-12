#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — media (mídias de artefatos)
#
# Gerencia /artifacts/media:
#   list --artifact <id>            GET    /artifacts/media?artifact_id=...  (artifact_id é obrigatório)
#   upload --artifact <id> --file f POST   /artifacts/media/upload           (multipart -F file=@...)
#   update <media-id> [campos]      PATCH  /artifacts/media/{id}             (parcial)
#   delete <media-id>               DELETE /artifacts/media/{id}             (pede confirmação)
#
# Uso:
#   media.sh [api-key] <subcomando> [argumentos/opções]
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_YES=1           pula a confirmação (PATCH/DELETE)
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
media.sh — mídias de artefatos do Chatvolt (/artifacts/media)

Uso:
  media.sh [api-key] <subcomando> [argumentos/opções]

Subcomandos:
  list --artifact <artifact-id> [--q <termo>] [--type <tipo>]
      Lista as mídias do artefato (GET /artifacts/media). A rota EXIGE
      artifact_id — sem ele a API responde 400. Tipos aceitos: IMAGE, VIDEO,
      AUDIO, DOCUMENT, OTHER (ou "all").

  upload --artifact <artifact-id> --file <caminho> [--name <nome>] [--alt <texto>]
      Envia um arquivo (multipart) e vincula ao artefato
      (POST /artifacts/media/upload). Campos: file, artifact_id, name
      (obrigatórios) e alt_description (opcional). Sem --name, usa o nome
      do arquivo.

  update <media-id> [--name <nome>] [--alt <texto>] [--active <bool>]
      Atualiza metadados (PATCH /artifacts/media/{id} — envio parcial).

  delete <media-id>
      Remove a mídia (DELETE /artifacts/media/{id}). Pede confirmação.

Opções comuns:
  -h, --help   mostra esta ajuda

Ambiente:
  CHATVOLT_API_KEY    API key (alternativa ao 1º argumento)
  CV_YES=1            pula a confirmação
  CV_JSON=1           imprime somente JSON em stdout
  CV_API_BASE         base URL alternativa (default https://api.chatvolt.ai)

Exit codes: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

source "$(dirname "$0")/_lib.sh"

is_subcmd() {
  case "$1" in list|upload|update|delete) return 0 ;; *) return 1 ;; esac
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

ARTIFACT=""
FILE=""
NAME=""
ALT=""
TYPE=""
Q=""
ACTIVE=""
MEDIA_ID=""
SEEN_NAME=0; SEEN_ALT=0; SEEN_ACTIVE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --artifact) ARTIFACT="${2:?--artifact exige o id do artefato}"; shift 2 ;;
    --file)     FILE="${2:?--file exige o caminho de um arquivo}"; shift 2 ;;
    --name)     NAME="${2:?--name exige um valor}"; SEEN_NAME=1; shift 2 ;;
    --alt)      ALT="${2:?--alt exige um texto}"; SEEN_ALT=1; shift 2 ;;
    --type)     TYPE="${2:?--type exige um tipo de mídia}"; shift 2 ;;
    --q)        Q="${2:?--q exige um termo}"; shift 2 ;;
    --active)   ACTIVE="${2:?--active exige true ou false}"; SEEN_ACTIVE=1; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         cv_die "opção desconhecida: $1 (use --help)" ;;
    *)          if [ -z "$MEDIA_ID" ]; then MEDIA_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

API_KEY=$(cv_req_key "$API_KEY_ARG")

case "$TYPE" in
  ""|IMAGE|VIDEO|AUDIO|DOCUMENT|OTHER|all) ;;
  # A API responde 500 com um tipo fora do enum — validamos aqui (exit 1).
  *) cv_die "--type inválido: $TYPE (use IMAGE, VIDEO, AUDIO, DOCUMENT, OTHER ou all)" ;;
esac
if [ "$SEEN_ACTIVE" = "1" ]; then
  case "$ACTIVE" in true|false|TRUE|FALSE|1|0|sim|nao) ;; *) cv_die "--active aceita true ou false" ;; esac
fi

read -r -d '' LIST_FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
if not isinstance(d, list) or not d:
    print("Nenhuma mídia encontrada.")
    raise SystemExit
print(f"{'ID':26} {'TIPO':10} {'NOME':38} {'ATIVO':6} ALT")
for m in d:
    print(f"{m.get('id',''):26} {m.get('mediaType',''):10} {str(m.get('name',''))[:38]:38} "
          f"{'sim' if m.get('isActive', True) else 'nao':6} {str(m.get('altDescription') or '-')[:40]}")
print(f"\nTotal: {len(d)}")
PY

read -r -d '' ONE_FORMATTER <<'PY' || true
import json, sys
m = json.load(sys.stdin)
if isinstance(m, dict) and "data" in m and "error" not in m:
    m = m["data"]
if not isinstance(m, dict) or not m:
    print("Mídia não encontrada.")
    raise SystemExit
print(f"ID:        {m.get('id','')}")
print(f"Nome:      {m.get('name','')}")
print(f"Tipo:      {m.get('mediaType','')}")
print(f"Artefato:  {m.get('artifactId','')}")
print(f"Ativo:     {'sim' if m.get('isActive', True) else 'nao'}")
print(f"Alt:       {m.get('altDescription') or '-'}")
print(f"URL:       {m.get('s3Url') or '-'}")
print(f"Criada em: {m.get('createdAt') or '-'}")
PY

read -r -d '' DELETE_FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "success" in d:
    print("Mídia deletada." if d.get("success") else "A API não confirmou a deleção.")
else:
    print(json.dumps(d, ensure_ascii=False))
PY

read -r -d '' UPLOAD_FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if not isinstance(d, dict):
    print(json.dumps(d, ensure_ascii=False))
    raise SystemExit
media = d.get("artifactMedia") if isinstance(d.get("artifactMedia"), dict) else {}
print(f"Mídia enviada: {media.get('name') or d.get('fileUrl') or '-'}")
print(f"ID:   {media.get('id') or '-'}")
print(f"Tipo: {media.get('mediaType') or '-'}")
print(f"URL:  {d.get('fileUrl') or media.get('s3Url') or '-'}")
PY

case "$SUBCMD" in
  list)
    [ -n "$MEDIA_ID" ] && cv_die "list não aceita argumento posicional (use --artifact)"
    [ -n "$ARTIFACT" ] || cv_die "list exige --artifact <id>: a API responde 400 sem artifact_id"
    ARGS=(--get --data-urlencode "artifact_id=${ARTIFACT}")
    [ -n "$Q" ] && ARGS+=(--data-urlencode "q=${Q}")
    [ -n "$TYPE" ] && ARGS+=(--data-urlencode "type=${TYPE}")
    cv_get "/artifacts/media" "${ARGS[@]}"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$LIST_FORMATTER"
    ;;

  upload)
    [ -n "$MEDIA_ID" ] && cv_die "upload não aceita argumento posicional (use --artifact/--file)"
    [ -n "$ARTIFACT" ] || cv_die "upload exige --artifact <id> (campo artifact_id do multipart)"
    [ -n "$FILE" ] || cv_die "upload exige --file <caminho>"
    [ -f "$FILE" ] || cv_die "arquivo não encontrado: $FILE"
    [ -r "$FILE" ] || cv_die "arquivo sem permissão de leitura: $FILE"
    UPLOAD_NAME="$NAME"
    [ -n "$UPLOAD_NAME" ] || UPLOAD_NAME="$(basename -- "$FILE")"
    cv_info "enviando $(basename -- "$FILE") ($(wc -c <"$FILE" | tr -d ' ') bytes) para o artefato ${ARTIFACT}"
    # Upload é multipart: -F file=@... (o helper não injeta Content-Type em
    # requisições sem corpo, então o curl monta o boundary corretamente).
    PARTS=(-F "file=@${FILE}" -F "artifact_id=${ARTIFACT}" -F "name=${UPLOAD_NAME}")
    [ -n "$ALT" ] && PARTS+=(-F "alt_description=${ALT}")
    cv_request POST "/artifacts/media/upload" "" "${PARTS[@]}"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$UPLOAD_FORMATTER"
    ;;

  update)
    [ -n "$MEDIA_ID" ] || cv_die "update exige o id da mídia"
    if [ "$SEEN_NAME$SEEN_ALT$SEEN_ACTIVE" = "000" ]; then
      cv_die "informe ao menos um campo (--name, --alt ou --active)"
    fi
    if ! PAYLOAD=$(python3 - "$NAME" "$ALT" "$ACTIVE" "$SEEN_NAME" "$SEEN_ALT" "$SEEN_ACTIVE" <<'PY'
import json, sys
name, alt, active, seen_name, seen_alt, seen_active = sys.argv[1:7]
p = {}
if seen_name == "1":
    p["name"] = name
if seen_alt == "1":
    p["altDescription"] = alt
if seen_active == "1":
    p["isActive"] = active.lower() in ("true", "1", "sim")
print(json.dumps(p, ensure_ascii=False))
PY
); then exit 1; fi
    cv_confirm "Aplicar PATCH em /artifacts/media/${MEDIA_ID}?"
    cv_request PATCH "/artifacts/media/${MEDIA_ID}" "$PAYLOAD"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$ONE_FORMATTER"
    ;;

  delete)
    [ -n "$MEDIA_ID" ] || cv_die "delete exige o id da mídia"
    cv_confirm "Deletar a mídia ${MEDIA_ID}? A deleção é permanente."
    cv_request DELETE "/artifacts/media/${MEDIA_ID}"
    cv_emit "$(cv_unwrap "$CV_RESP")" "$DELETE_FORMATTER"
    ;;
esac
