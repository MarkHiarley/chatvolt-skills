#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — delete-artifact
#
# Remove um artefato (DELETE /artifacts/{id}?action=delete), alterna o estado
# ativo/inativo (action=toggle) ou remove vários de uma vez (DELETE /artifacts
# com {"ids":[...]}). Antes de qualquer coisa destrutiva o script lê o artefato
# (somente leitura) para mostrar o que será afetado e pede confirmação.
#
# Uso:
#   delete-artifact.sh [api-key] <artifact-id> [--toggle]
#   delete-artifact.sh [api-key] --ids <id1,id2,...>
#
# Opções:
#   --toggle       em vez de deletar, alterna isActive (action=toggle)
#   --ids <lista>  deleção em lote (ids separados por vírgula)
#   -h, --help
#
# Ambiente:
#   CHATVOLT_API_KEY   alternativa à api-key como 1º argumento
#   CV_YES=1           pula a confirmação (operação destrutiva)
#   CV_JSON=1          imprime SOMENTE JSON em stdout (diagnósticos em stderr)
#   CV_API_BASE        sobrescreve a base URL (teste offline)

usage() {
  cat <<'EOF'
delete-artifact.sh — deleta (ou alterna) artefatos do Chatvolt

Uso:
  delete-artifact.sh [api-key] <artifact-id> [--toggle]
  delete-artifact.sh [api-key] --ids <id1,id2,...>

Argumentos:
  <artifact-id>  id do artefato

Opções:
  --toggle       alterna isActive do artefato (action=toggle) em vez de deletar
  --ids <lista>  deleção em lote (DELETE /artifacts com {"ids":[...]})
  -h, --help     mostra esta ajuda

A deleção é permanente. Sem CV_YES=1 o script pede confirmação (exit 130 se
o usuário responder não). Não existe deleção em lote com --toggle.

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
IDS=""
TOGGLE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --toggle)  TOGGLE=1; shift ;;
    --ids)     IDS="${2:?--ids exige uma lista de ids separados por vírgula}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        cv_die "opção desconhecida: $1 (use --help)" ;;
    *)         if [ -z "$ART_ID" ]; then ART_ID="$1"; shift; else cv_die "argumento extra: $1"; fi ;;
  esac
done

if [ -n "$IDS" ]; then
  [ -n "$ART_ID" ] && cv_die "use <artifact-id> OU --ids, não os dois"
  [ "$TOGGLE" = "1" ] && cv_die "--toggle só funciona com um único artefato (--ids é deleção em lote)"
else
  [ -n "$ART_ID" ] || { usage >&2; cv_die "informe o id do artefato ou use --ids"; }
fi

API_KEY=$(cv_req_key "$API_KEY_ARG")

if [ -n "$IDS" ]; then
  # Deleção em lote: DELETE /artifacts com {"ids":[...]}.
  if ! PAYLOAD=$(python3 - "$IDS" <<'PY'
import json, sys
ids = [i.strip() for i in sys.argv[1].split(",") if i.strip()]
if not ids:
    print("ERRO: --ids não contém nenhum id", file=sys.stderr)
    raise SystemExit(1)
print(json.dumps({"ids": ids}, ensure_ascii=False))
PY
); then exit 1; fi

  N=$(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["ids"]))')
  cv_info "artefatos a deletar (${N}): $(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; print(", ".join(json.load(sys.stdin)["ids"]))')"
  cv_confirm "Deletar ${N} artefato(s) em lote? A deleção é permanente."

  cv_request DELETE "/artifacts" "$PAYLOAD"
  RESP=$(cv_unwrap "$CV_RESP")

  read -r -d '' FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    print(f"Artefatos deletados: {d.get('count', '?')}")
    if d.get("message"):
        print(d["message"])
else:
    print(json.dumps(d, ensure_ascii=False))
PY

  cv_emit "$RESP" "$FORMATTER"
  exit 0
fi

# 1) Mostra o que será afetado (somente leitura).
cv_get "/artifacts/${ART_ID}"
CUR=$(cv_unwrap "$CV_RESP")
NAME=$(printf '%s' "$CUR" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("name") or "" if isinstance(d, dict) else "")')
cv_info "artefato: ${NAME:-?} (${ART_ID})"

if [ "$TOGGLE" = "1" ]; then
  cv_confirm "Alternar isActive do artefato ${ART_ID}?"
  ACTION="toggle"
else
  cv_confirm "Deletar o artefato ${ART_ID}? A deleção é permanente (as mídias vinculadas saem junto)."
  ACTION="delete"
fi

cv_request DELETE "/artifacts/${ART_ID}?action=${ACTION}"
RESP=$(cv_unwrap "$CV_RESP")

read -r -d '' FORMATTER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    print(f"{d.get('name','')} ({d.get('id','')}) — ativo: {'sim' if d.get('isActive') else 'nao'}")
else:
    print(json.dumps(d, ensure_ascii=False))
PY

cv_emit "$RESP" "$FORMATTER"
