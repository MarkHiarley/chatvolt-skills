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

# cv_check_updates — verifica se a API/doc mudaram desde a última vez. Roda no
# carregamento de toda skill (scripts/check-updates.sh). Compara:
#   1. o OpenAPI publicado com o catálogo api-call/data/endpoints.json;
#   2. as operações de apps/docs (fonte do docs.chatvolt.ai) com o catálogo;
#   3. o HEAD do monorepo appchatvolt_dev com o último visto (se o clone existir).
# Nunca falha: sem rede ou sem clone local vira uma linha de aviso.
#   CV_UPDATE_CHECK=0  desliga a verificação
#   CV_OPENAPI_URL     spec publicado (default: https://chat-volt.mintlify.app/openapi.yaml)
#   CV_SRC             monorepo appchatvolt_dev (default: ~/Área de trabalho/ChatvoltRepositorios/appchatvolt_dev)
#   CV_STATE_DIR       estado entre execuções (default: ~/.local/state/chatvolt-skills)
cv_check_updates() {
  [ "${CV_UPDATE_CHECK:-1}" = "0" ] && return 0
  local here catalog state_dir report
  here="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
  catalog="$here/../../api-call/data/endpoints.json"
  state_dir="${CV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/chatvolt-skills}"
  mkdir -p "$state_dir" 2>/dev/null || return 0
  report=$(
    CV_OPENAPI_URL="${CV_OPENAPI_URL:-https://chat-volt.mintlify.app/openapi.yaml}" \
    CV_SRC="${CV_SRC:-$HOME/Área de trabalho/ChatvoltRepositorios/appchatvolt_dev}" \
    CV_CATALOG="$([ -f "$catalog" ] && realpath "$catalog")" \
    CV_STATE_FILE="$state_dir/updates.json" \
    python3 - <<'PY' 2>/dev/null
import datetime, glob, hashlib, json, os, re, subprocess, sys, urllib.request

URL = os.environ["CV_OPENAPI_URL"]
SRC = os.environ.get("CV_SRC", "")
CATALOG = os.environ.get("CV_CATALOG", "")
STATE_FILE = os.environ["CV_STATE_FILE"]

def norm(method, path):
    # Parâmetros de rota viram "{}" e o prefixo /api (usado só na doc-fonte) sai.
    p = re.sub(r"\{[^}]+\}", "{}", path.rstrip("/") or "/")
    if p.startswith("/api/"):
        p = p[4:]
    return f"{method.upper()} {p}"

try:
    with open(STATE_FILE, encoding="utf-8") as f:
        state = json.load(f)
except Exception:
    state = {}

new_state = dict(state)
new_state["checked_at"] = datetime.datetime.now().isoformat(timespec="seconds")
lines = []
known = set()
catalog_label = "catálogo salvo"

if CATALOG and os.path.isfile(CATALOG):
    with open(CATALOG, encoding="utf-8") as f:
        cat = json.load(f)
    known = {norm(o["method"], o["path"]) for o in cat.get("operations", [])}
    catalog_label = "catálogo api-call"
else:
    known = set(state.get("known_ops", []))

# 1. OpenAPI publicado
doc_ops = None
try:
    req = urllib.request.Request(URL, headers={"User-Agent": "chatvolt-skills-update-check"})
    raw = urllib.request.urlopen(req, timeout=10).read()
    sha = hashlib.sha256(raw).hexdigest()[:12]
    doc_ops = set()
    current = None
    for line in raw.decode("utf-8", "replace").splitlines():
        m = re.match(r"^  (/\S*):\s*$", line)
        if m:
            current = m.group(1)
            continue
        m = re.match(r"^    (get|post|put|patch|delete):\s*$", line)
        if m and current:
            doc_ops.add(norm(m.group(1), current))
    if not known:
        known = set(doc_ops)
        new_state["known_ops"] = sorted(known)
    prev_sha = state.get("doc_sha")
    prev_ops = set(state.get("doc_ops", []))
    if prev_sha is None:
        lines.append(f"OpenAPI: primeira verificação ({len(doc_ops)} operações, sha {sha})")
    elif prev_sha != sha:
        added = sorted(doc_ops - prev_ops)
        removed = sorted(prev_ops - doc_ops)
        lines.append(f"OpenAPI MUDOU: +{len(added)} / -{len(removed)} operações (sha {prev_sha} → {sha})")
        lines += [f"   + {o}" for o in added[:10]]
        lines += [f"   - {o}" for o in removed[:10]]
    else:
        lines.append(f"OpenAPI: sem mudanças desde a última verificação (sha {sha})")
    gaps = sorted(doc_ops - known)
    if gaps:
        lines.append(f"Catálogo desatualizado: {len(gaps)} operação(ões) da doc fora do {catalog_label}")
        lines += [f"   + {o}" for o in gaps[:10]]
    new_state["doc_sha"] = sha
    new_state["doc_ops"] = sorted(doc_ops)
except Exception as exc:
    lines.append(f"OpenAPI: não consegui consultar ({type(exc).__name__}); verificação pulada")

def git(*args):
    return subprocess.run(["git", "-C", SRC, *args], capture_output=True, text=True, timeout=15)

# 2 e 3. Monorepo local: fonte da doc (apps/docs) e rotas (apps/dashboard/pages/api)
if SRC and os.path.exists(os.path.join(SRC, ".git")):
    head_proc = git("rev-parse", "HEAD")
    head = head_proc.stdout.strip() if head_proc.returncode == 0 else ""
    if head:
        docs_ops = set()
        for root, dirs, files in os.walk(os.path.join(SRC, "apps", "docs")):
            dirs[:] = [d for d in dirs if d != "node_modules"]
            for name in files:
                if not name.endswith(".mdx"):
                    continue
                with open(os.path.join(root, name), encoding="utf-8", errors="ignore") as f:
                    text = f.read()
                for m in re.finditer(r'^openapi:\s*["\']?(GET|POST|PUT|PATCH|DELETE)\s+(\S+?)["\']?\s*$', text, re.M):
                    op = norm(m.group(1), m.group(2))
                    if not op.endswith(" /"):
                        docs_ops.add(op)
        gaps = sorted(docs_ops - known)
        if gaps:
            lines.append(f"Fonte da doc (apps/docs): {len(gaps)} operação(ões) fora do {catalog_label}")
            lines += [f"   + {o}" for o in gaps[:10]]

        prev = state.get("src_head")
        if prev is None:
            lines.append(f"Código-fonte ({os.path.basename(SRC)}): baseline em {head[:8]}")
        elif prev != head:
            diff = git("diff", "--name-only", prev, head, "--", "apps/dashboard/pages/api", "apps/docs")
            if diff.returncode == 0:
                files = [x for x in diff.stdout.split("\n") if x]
                lines.append(f"Código-fonte MUDOU: {len(files)} arquivo(s) de API/doc ({prev[:8]} → {head[:8]})")
                lines += [f"   ~ {x}" for x in files[:10]]
            else:
                lines.append(f"Código-fonte mudou ({prev[:8]} → {head[:8]}), mas o commit anterior não está no clone local")
        else:
            lines.append(f"Código-fonte: sem mudanças desde a última verificação ({head[:8]})")
        behind = git("rev-list", "--count", "HEAD..@{u}")
        if behind.returncode == 0 and behind.stdout.strip() not in ("", "0"):
            lines.append(f"Clone local está {behind.stdout.strip()} commit(s) atrás do remoto: rode git pull em {SRC} para ver o mais novo")
        new_state["src_head"] = head

try:
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(new_state, f, ensure_ascii=False, indent=2)
except Exception:
    pass

if lines:
    print("Atualizações Chatvolt:")
    print("\n".join("  " + l if not l.startswith("   ") else l for l in lines))
PY
  ) || true
  [ -n "$report" ] && cv_info "$report"
  return 0
}
