#!/usr/bin/env bash
# show-source-tags.sh — mostra as etiquetas/custom_id de UMA fonte da base.
#
# Lê GET /datasources/{id}?idstore={datastoreId} (o único GET de fonte que existe:
# exige o parâmetro idstore) e destaca config.tags e config.custom_id.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: show-source-tags.sh <api-key> <datastore-id> <source-id>

Mostra os metadados de uma fonte: etiquetas (config.tags), custom_id,
status de indexação, tamanho do texto e hash do conteúdo.

Argumentos:
  <api-key>          Chave de API (ou exporte CHATVOLT_API_KEY)
  <datastore-id>     ID da base (sufixo _v3) — vira o parâmetro ?idstore=
  <source-id>        ID da fonte (datasource)

Exemplos:
  show-source-tags.sh "$CHATVOLT_API_KEY" cmszh5s6q0fbdvapf36roho4y_v3 cmszhb44818w3sfqp97pi29h1
  CV_JSON=1 show-source-tags.sh "$CHATVOLT_API_KEY" <base> <fonte>   # JSON cru da fonte

Saída (CV_JSON=1): o objeto da fonte exatamente como a API devolve
  (id, type, name, status, config{tags,custom_id,mime_type,file_url}, nbChunks,
   textSize, nbTokens, hash, lastSynch …)

Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift
DS="${1:-}"; shift || true
SRC="${1:-}"; shift || true
[ -n "$DS" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$SRC" ] || { usage >&2; cv_die "informe o <source-id>"; }
[ $# -eq 0 ] || { usage >&2; cv_die "argumento extra inesperado: $1"; }

cv_get "/datasources/${SRC}?idstore=${DS}"

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$CV_RESP"
else
  printf '%s' "$CV_RESP" | python3 -c 'import json,sys
d = json.load(sys.stdin)
cfg = d.get("config") or {}
tags = [str(t) for t in (cfg.get("tags") or [])]
custom = cfg.get("custom_id")
print("Fonte:       " + str(d.get("name")))
print("ID:          " + str(d.get("id")))
print("Base:        " + str(d.get("datastoreId")))
print("Tipo:        " + str(d.get("type")))
print("Status:      " + str(d.get("status")) + "   (nbSynch " + str(d.get("nbSynch")) + ")")
print("Conteúdo:    nbChunks " + str(d.get("nbChunks")) + " · textSize " + str(d.get("textSize"))
      + " bytes · nbTokens " + str(d.get("nbTokens")))
print("Hash:        " + str(d.get("hash")))
print("Criada em:   " + str(d.get("createdAt")))
print("Atualizada:  " + str(d.get("updatedAt")))
print("")
print("Etiquetas (" + str(len(tags)) + "): " + (", ".join(tags) if tags else "(nenhuma)"))
print("custom_id:   " + (str(custom) if custom else "(não definido)"))
if cfg.get("mime_type") or cfg.get("file_url"):
    print("mime_type:   " + str(cfg.get("mime_type") or "-"))
    if cfg.get("file_url"):
        print("file_url:    " + str(cfg.get("file_url")))
print("")
print("Etiqueta = metadado local: a API NÃO filtra a busca por ela (use find-by-tag.sh).")
print("custom_id = filtro real de recuperação (filters.custom_ids na query):")
if custom:
    print("  set-custom-id.sh <api-key> " + str(d.get("datastoreId")) + " " + str(d.get("id")) + " <valor> --reuse-text")
    print("  query-verify.sh  <api-key> " + str(d.get("datastoreId")) + " \"<pergunta>\" --custom-id " + str(custom))
else:
    print("  (defina um custom_id para segmentar a recuperação por tenant/cliente)")
'
fi
