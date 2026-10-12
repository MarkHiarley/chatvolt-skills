#!/usr/bin/env bash
# _lib.sh — helpers comuns das skills Chatvolt.
#
# ATENÇÃO: este arquivo deve ser IDÊNTICO em todas as skills
# (*/scripts/_lib.sh). A suíte de testes verifica isso por sha256.
# Contrato HTTP completo: SOURCES.md na raiz do repo.
#
# Variáveis respeitadas:
#   CV_API_BASE     base URL (default: https://api.chatvolt.ai; usado pelo stub de teste)
#   CV_JSON=1       imprime SOMENTE JSON em stdout; diagnósticos vão para stderr
#   CV_MAX_RETRIES  tentativas em HTTP 429 (default 3)
#   CV_RETRY_WAIT   segundos entre tentativas de 429 (default 5)
#   CV_TIMEOUT      timeout do curl em segundos (default 120)

CV_BASE_URL="${CV_API_BASE:-https://api.chatvolt.ai}"
CV_JSON="${CV_JSON:-0}"
CV_STATUS=""
CV_RESP=""

cv_die() { echo "ERRO: $*" >&2; exit "${2:-1}"; }

# cv_info <msg> — diagnóstico: stderr em modo JSON, stdout em modo humano.
cv_info() { if [ "$CV_JSON" = "1" ]; then echo "$*" >&2; else echo "$*"; fi; }

# cv_warn <msg> — sempre em stderr.
cv_warn() { echo "AVISO: $*" >&2; }

# cv_req_key — resolve a API key de argv ou do ambiente.
cv_req_key() {
  local key="${1:-${CHATVOLT_API_KEY:-}}"
  [ -n "$key" ] || cv_die "informe a API key como 1o argumento ou exporte CHATVOLT_API_KEY"
  printf '%s' "$key"
}

# cv_err_msg <json> — extrai a mensagem de qualquer formato de erro observado:
#   {"error":"CODE"} | {"error":{"message","code"}} | {"message":"..."}
#   | {"data":null,"success":false,"error":{...}}
cv_err_msg() {
  printf '%s' "$1" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print((raw or "resposta vazia").strip()[:300]); raise SystemExit
if isinstance(d, dict):
    for k in ("error", "message"):
        v = d.get(k)
        if isinstance(v, dict):
            print(v.get("message") or v.get("code") or json.dumps(v, ensure_ascii=False)); raise SystemExit
        if isinstance(v, str) and v.strip():
            print(v.strip()); raise SystemExit
print(json.dumps(d, ensure_ascii=False)[:300])
' 2>/dev/null || printf '%s' "$1"
}

# cv_unwrap <json> — aplica o envelope {data,...} das rotas de listagem.
# Só desembrulha quando o dict tem "data" e NÃO tem "error":
#   /datastores/list e /datasources/list → {data:[...], pagination:{...}}
#   /agents, /conversation, /datastores/{id} → já vêm na raiz (sem envelope)
cv_unwrap() {
  printf '%s' "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d:
    d = d["data"]
print(json.dumps(d, ensure_ascii=False))
'
}

# cv_json — normaliza um JSON recebido como argumento (uso interno).
cv_json() {
  python3 -c 'import json, sys; print(json.dumps(json.loads(sys.argv[1]), ensure_ascii=False))' "$1"
}

# cv_emit <json> [<comando-python-de-formatação>] — saída respeitando CV_JSON=1.
# CV_JSON=1 → JSON cru; senão → roda o formatador (default: json.tool).
cv_emit() {
  if [ "$CV_JSON" = "1" ]; then
    printf '%s\n' "$1"
  else
    printf '%s' "$1" | python3 -c "${2:-import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))}"
  fi
}

# cv_request <METHOD> <path> [json-body] [args extras do curl...]
# Define CV_STATUS e CV_RESP; trata erros HTTP com mensagens acionáveis.
# Sai com: 1 = erro do cliente, 3 = quota (402), 4 = falha de rede, 5 = erro 5xx.
cv_request() {
  local method="$1" path="$2" body="${3:-}"
  shift 2
  [ $# -gt 0 ] && shift

  local attempt=0 out
  while :; do
    if [ -n "$body" ]; then
      out=$(curl -sS --max-time "${CV_TIMEOUT:-120}" -w $'\n%{http_code}' -X "$method" \
              -H "Authorization: Bearer ${API_KEY}" -H 'Content-Type: application/json' \
              --data-binary "$body" "$@" "${CV_BASE_URL}${path}") || cv_die "falha de rede em ${method} ${path}" 4
    else
      out=$(curl -sS --max-time "${CV_TIMEOUT:-120}" -w $'\n%{http_code}' -X "$method" \
              -H "Authorization: Bearer ${API_KEY}" "$@" "${CV_BASE_URL}${path}") || cv_die "falha de rede em ${method} ${path}" 4
    fi
    CV_STATUS="${out##*$'\n'}"
    CV_RESP="${out%$'\n'*}"

    if [ "$CV_STATUS" = "429" ]; then
      attempt=$((attempt + 1))
      [ "$attempt" -ge "${CV_MAX_RETRIES:-3}" ] && cv_die "HTTP 429 (rate limit: 60 req/min, 10k/dia): $(cv_err_msg "$CV_RESP")"
      cv_warn "HTTP 429 — aguardando ${CV_RETRY_WAIT:-5}s (tentativa ${attempt}/${CV_MAX_RETRIES:-3})"
      sleep "${CV_RETRY_WAIT:-5}"
      continue
    fi
    break
  done

  case "$CV_STATUS" in
    2*) return 0 ;;
    400) cv_die "HTTP 400 (requisição inválida): $(cv_err_msg "$CV_RESP")" ;;
    401|403) cv_die "HTTP ${CV_STATUS} (não autorizado): $(cv_err_msg "$CV_RESP") — confira a API key e as permissões da organização" ;;
    402) cv_die "HTTP 402 (quota): limite de uso mensal do plano atingido — $(cv_err_msg "$CV_RESP")" 3 ;;
    404) cv_die "HTTP 404 (não encontrado): $(cv_err_msg "$CV_RESP")" ;;
    406) cv_die "HTTP 406 (sessão do canal expirada): $(cv_err_msg "$CV_RESP")" ;;
    5*)  cv_die "HTTP ${CV_STATUS} (erro interno do servidor): $(cv_err_msg "$CV_RESP")" 5 ;;
    *)   cv_die "HTTP ${CV_STATUS}: $(cv_err_msg "$CV_RESP")" ;;
  esac
}

# cv_get <path> [args extras do curl...]
cv_get() { local p="$1"; shift; cv_request GET "$p" "" "$@"; }

# cv_json_get <path> <chave> [args extras do curl...] — imprime a chave de um objeto.
cv_json_get() {
  local path="$1" key="$2"; shift 2
  cv_get "$path" "$@"
  printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict) and "data" in d and "error" not in d: d = d["data"]
print(d.get(sys.argv[1], ""))
' "$key"
}

# cv_confirm <pergunta> — confirmação humana; CV_YES=1 aprova automaticamente.
cv_confirm() {
  [ "${CV_YES:-0}" = "1" ] && return 0
  local answer
  printf '%s [s/N] ' "$1" >&2
  read -r answer
  case "$answer" in s|S|sim|SIM|y|Y|yes) return 0 ;; *) echo "Cancelado." >&2; exit 130 ;; esac
}
