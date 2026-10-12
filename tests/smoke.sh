#!/usr/bin/env bash
# tests/smoke.sh — verificação headless das skills Chatvolt.
#
#   ./tests/smoke.sh --lint            só verificação estática (sem rede)
#   ./tests/smoke.sh --stub            lint + execução contra o stub local (sem rede externa)
#   ./tests/smoke.sh --live            lint + leituras reais (exige CHATVOLT_API_KEY)
#   ./tests/smoke.sh --live --mutating inclui escrita real em recursos descartáveis (OMP-SMOKE-*)
#   ./tests/smoke.sh --probe           grava a resposta crua dos endpoints em tests/probe/latest.json
#   ./tests/smoke.sh --all             lint + stub + live (sem mutating)
#
# Variáveis: CHATVOLT_API_KEY, CHATVOLT_AGENT_ID, CHATVOLT_DATASTORE_ID, CHATVOLT_CONVERSATION_ID
# Contrato HTTP e formas de resposta: SOURCES.md

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="--lint"
MUTATING=0
for arg in "$@"; do
  case "$arg" in
    --lint|--stub|--live|--probe|--all) MODE="$arg" ;;
    --mutating) MUTATING=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 64 ;;
  esac
done

PASS=0
FAIL=0
SKIP=0

ok()   { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf '  \033[33mSKIP\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

SKILLS=(agent-test investigation prompt-adjust tools-update conversation-cleanup datastore-add datastore-tags)

# ── Lint ─────────────────────────────────────────────────────────────────
lint() {
  head_ "lint: sintaxe bash"
  local f
  while IFS= read -r f; do
    if bash -n "$f" 2>/dev/null; then ok "bash -n ${f#./}"; else bad "bash -n ${f#./}"; fi
  done < <(find . -name '*.sh' -not -path './.git/*' | sort)

  head_ "lint: _lib.sh idêntico em todas as skills"
  local hashes
  hashes=$(sha256sum */scripts/_lib.sh | awk '{print $1}' | sort -u | wc -l)
  if [ "$hashes" = "1" ]; then ok "_lib.sh igual em ${#SKILLS[@]} skills"; else bad "_lib.sh divergente entre skills ($hashes versões)"; fi

  head_ "lint: cada skill tem SKILL.md com name: chatvolt-<ref>"
  local s
  for s in "${SKILLS[@]}"; do
    if [ ! -f "$s/SKILL.md" ]; then bad "$s/SKILL.md ausente"; continue; fi
    if grep -q "^name: chatvolt-$s$" "$s/SKILL.md"; then ok "$s/SKILL.md (name correto)"; else bad "$s/SKILL.md sem 'name: chatvolt-$s'"; fi
  done

  head_ "lint: scripts usam _lib.sh e são executáveis"
  for s in "${SKILLS[@]}"; do
    local n=0 src=0
    while IFS= read -r f; do
      n=$((n + 1))
      [ -x "$f" ] || { bad "$f não é executável"; }
      grep -q '_lib.sh' "$f" || { bad "${f#./} não carrega _lib.sh"; }
      src=$((src + 1))
    done < <(find "$s/scripts" -name '*.sh' ! -name '_lib.sh' | sort)
    if [ "$src" -gt 0 ]; then ok "$s: $n scripts (todos com _lib.sh)"; else bad "$s sem scripts"; fi
  done

  head_ "lint: padrões proibidos (contratos que a doc/API não têm)"
  local pattern hits
  for pattern in 'chatvolt\.ai/api/agents' 'organizationId=' '^[^#]*POST[^)]*/webhook' '^[^#]*curl[^|]*webhook[^?]' 'open.?closed.?waiting'; do
    hits=$(grep -rInE "$pattern" --include='*.sh' */scripts 2>/dev/null || true)
    if [ -z "$hits" ]; then ok "sem ocorrências de /$pattern/"; else bad "padrão proibido /$pattern/: $(echo "$hits" | head -3)"; fi
  done

  head_ "lint: endpoints usados existem no contrato"
  local ep
  for ep in '/api/agents' '/conversations?' '/agents/create' '/agents/models/' ; do
    hits=$(grep -rInF "$ep" --include='*.sh' */scripts 2>/dev/null || true)
    if [ -z "$hits" ]; then ok "nenhum uso de '$ep'"; else bad "uso inválido de '$ep': $(echo "$hits" | head -2)"; fi
  done
}

# ── Stub offline ─────────────────────────────────────────────────────────
STUB_PID=""
STUB_PORT=""
stub_start() {
  python3 tests/stub_server.py 0 > /tmp/cv-stub.port 2>/dev/null &
  STUB_PID=$!
  for _ in $(seq 1 50); do
    STUB_PORT=$(cat /tmp/cv-stub.port 2>/dev/null || true)
    [ -n "$STUB_PORT" ] && break
    sleep 0.1
  done
  [ -n "$STUB_PORT" ] || { echo "não consegui subir o stub" >&2; exit 1; }
}
stub_stop() { [ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null; wait "$STUB_PID" 2>/dev/null; }

# assert_run <descrição> <texto esperado> <exit esperado> <cmd...>
assert_run() {
  local desc="$1" want_out="$2" want_exit="$3"
  shift 3
  local out rc
  if declare -F "$1" >/dev/null 2>&1; then
    out=$("$@" 2>&1)          # função interna: não passa por `timeout`
  else
    out=$(timeout "${CV_TEST_TIMEOUT:-30}" "$@" 2>&1)
  fi
  rc=$?
  if [ "$rc" = "124" ]; then bad "$desc (timeout de ${CV_TEST_TIMEOUT:-30}s — comando travou)"; return 1; fi
  if [ "$rc" != "$want_exit" ]; then bad "$desc (exit=$rc, esperado $want_exit): $(printf '%s' "$out" | head -2 | tr '\n' ' ')"; return 1; fi
  if [ -n "$want_out" ] && ! printf '%s' "$out" | grep -qF "$want_out"; then bad "$desc (saída sem '$want_out'): $(printf '%s' "$out" | head -2 | tr '\n' ' ')"; return 1; fi
  ok "$desc"
  return 0
}

stub_tests() {
  head_ "stub: leituras (CV_API_BASE local)"
  export CV_API_BASE="http://127.0.0.1:${STUB_PORT}" CV_MAX_RETRIES=3 CV_RETRY_WAIT=0 CV_YES=1
  local K="stub-key"

  assert_run "agent-test/get-agent.sh" "Agente Stub" 0 ./agent-test/scripts/get-agent.sh "$K" agent-1
  assert_run "agent-test/send-query.sh (nova conversa)" "PONG-STUB" 0 ./agent-test/scripts/send-query.sh "$K" agent-1 "oi"
  assert_run "investigation/list-conversations.sh" "conv-api-1" 0 ./investigation/scripts/list-conversations.sh "$K" agent-1 --days 30
  assert_run "investigation/get-messages.sh" "Bom dia" 0 ./investigation/scripts/get-messages.sh "$K" conv-api-1 2
  assert_run "prompt-adjust/list-models.sh" "gpt_54_nano" 0 ./prompt-adjust/scripts/list-models.sh "$K"
  assert_run "tools-update/list-tools.sh" "consultar_status" 0 ./tools-update/scripts/list-tools.sh "$K" agent-1
  assert_run "conversation-cleanup/list-conversations.sh" "conv-wa-1" 0 ./conversation-cleanup/scripts/list-conversations.sh "$K" --agent agent-1
  assert_run "datastore-add/list-datastores.sh" "Base Stub" 0 ./datastore-add/scripts/list-datastores.sh "$K"
  assert_run "datastore-add/list-sources.sh" "politica.md" 0 ./datastore-add/scripts/list-sources.sh "$K" ds-1
  assert_run "datastore-add/query-base.sh" "devolução" 0 ./datastore-add/scripts/query-base.sh "$K" ds-1 "politica de devolucao"
  assert_run "datastore-tags/list-tags.sh" "faq" 0 ./datastore-tags/scripts/list-tags.sh "$K" ds-1
  assert_run "datastore-tags/find-by-tag.sh" "politica.md" 0 ./datastore-tags/scripts/find-by-tag.sh "$K" ds-1 faq

  head_ "stub: escritas"
  assert_run "prompt-adjust/toggle-webhook.sh" "telegram webhook disabled" 0 ./prompt-adjust/scripts/toggle-webhook.sh "$K" agent-1 telegram off
  assert_run "datastore-add/create-datastore.sh" "ds-nova-1" 0 ./datastore-add/scripts/create-datastore.sh "$K" --name "Base Smoke"
  assert_run "datastore-add/add-source.sh (texto)" "synched" 0 ./datastore-add/scripts/add-source.sh "$K" ds-1 --text "conteudo de teste" --name doc.md --tags a,b
  assert_run "datastore-tags/set-tags.sh (metadados)" "tag-a" 0 ./datastore-tags/scripts/set-tags.sh "$K" ds-1 src-1 --tags tag-a,tag-b
  assert_run "datastore-tags/add-tag.sh" "" 0 ./datastore-tags/scripts/add-tag.sh "$K" ds-1 src-1 smoke
  assert_run "datastore-tags/query-verify.sh (filtro inválido -> vazio)" "" 0 ./datastore-tags/scripts/query-verify.sh "$K" ds-1 "politica" --custom-id outro-tenant --expect-empty
  assert_run "datastore-add/attach-to-agent.sh" "" 0 ./datastore-add/scripts/attach-to-agent.sh "$K" agent-1 ds-1
  assert_run "tools-update/delete-tool.sh" "" 0 ./tools-update/scripts/delete-tool.sh "$K" agent-1 tool-1
  assert_run "tools-update/update-tool.sh" "" 0 ./tools-update/scripts/update-tool.sh "$K" agent-1 tool-2 '{"type":"datastore","datastoreId":"ds-1"}'

  head_ "stub: erros (key inválida, quota, rate limit, guarda de conversa)"
  assert_run "key inválida -> exit 1" "não autorizado" 1 ./agent-test/scripts/get-agent.sh "key-errada" agent-1
  assert_run "quota 402 -> exit 3" "" 3 ./datastore-add/scripts/query-base.sh "$K" quota-me "x"
  assert_run "429 com retry -> exit 0" "PASS" 0 bash -c 'out=$(./tools-update/scripts/list-tools.sh stub-key flaky); printf "%s" "$out" | grep -q consultar_status && echo PASS'
  assert_run "conversa existente sem --force -> exit 2" "" 2 ./agent-test/scripts/send-query.sh "$K" agent-1 "oi" --conversation conv-api-1
}

# ── Live ─────────────────────────────────────────────────────────────────
# Cada helper valida o CONTRATO (CV_JSON=1 + campos reais), não o layout humano.
live_check_get_agent() {
  CV_JSON=1 ./agent-test/scripts/get-agent.sh "$1" "$2" | python3 -c 'import json,sys
d = json.load(sys.stdin)
a = d.get("agent", d)
assert a.get("name") and a.get("modelName") and a.get("systemPrompt") is not None, list(a)[:8]
print("PASS")'
}

live_check_models() {
  CV_JSON=1 ./prompt-adjust/scripts/list-models.sh "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin)
assert isinstance(d, list) and d and "model_name" in d[0], repr(d)[:120]
print("PASS")
print(f"  {len(d)} modelos", file=sys.stderr)'
}

live_check_conversations() {
  CV_JSON=1 ./investigation/scripts/list-conversations.sh "$1" "$2" --days 7 --limit 3 | python3 -c 'import json,sys
d = json.load(sys.stdin)
assert isinstance(d, list), type(d).__name__
for c in d:
    assert c.get("id") and c.get("channel"), c
    assert c.get("status") in {"RESOLVED", "UNRESOLVED", "HUMAN_REQUESTED"}, c.get("status")
print("PASS")'
}

live_tests() {
  local K="${CHATVOLT_API_KEY:-}"
  local A="${CHATVOLT_AGENT_ID:-}"
  local DS="${CHATVOLT_DATASTORE_ID:-}"
  local CV="${CHATVOLT_CONVERSATION_ID:-}"
  head_ "live: leituras reais"
  if [ -z "$K" ] || [ -z "$A" ]; then
    skip "CHATVOLT_API_KEY/CHATVOLT_AGENT_ID não definidos — pulando live"
    return 0
  fi
  unset CV_API_BASE
  assert_run "live get-agent.sh (objeto na raiz com name/modelName/systemPrompt)" "PASS" 0 live_check_get_agent "$K" "$A"
  assert_run "live list-models.sh (array com model_name)" "PASS" 0 live_check_models "$K"
  assert_run "live list-conversations.sh (array com id/channel/status válidos)" "PASS" 0 live_check_conversations "$K" "$A"
  assert_run "live list-tools.sh" "" 0 ./tools-update/scripts/list-tools.sh "$K" "$A"
  if [ -n "$CV" ]; then assert_run "live get-messages.sh" "" 0 ./investigation/scripts/get-messages.sh "$K" "$CV" 5; else skip "get-messages.sh (defina CHATVOLT_CONVERSATION_ID)"; fi
  if [ -n "$DS" ]; then
    assert_run "live list-sources.sh" "" 0 ./datastore-add/scripts/list-sources.sh "$K" "$DS"
    assert_run "live list-tags.sh" "" 0 ./datastore-tags/scripts/list-tags.sh "$K" "$DS"
    assert_run "live query-base.sh" "" 0 ./datastore-add/scripts/query-base.sh "$K" "$DS" "teste" --top-k 1
  else
    skip "datastore-add/datastore-tags live (defina CHATVOLT_DATASTORE_ID)"
  fi
}

# ── Live mutante (recursos descartáveis OMP-SMOKE-*) ─────────────────────
mutating_tests() {
  local K="${CHATVOLT_API_KEY:-}"
  head_ "live --mutating: escrita em recursos descartáveis"
  if [ -z "$K" ]; then skip "sem CHATVOLT_API_KEY — pulando mutating"; return 0; fi
  unset CV_API_BASE
  local ts ds
  ts=$(date +%s)

  # Base de conhecimento: criar é permitido mesmo com a cota de agentes esgotada.
  ds=$(./datastore-add/scripts/create-datastore.sh "$K" --name "OMP-SMOKE-DS-$ts" --description "base descartável de smoke test" 2>/dev/null | grep -oE 'cm[a-z0-9_]{10,}' | head -1 || true)
  if [ -z "$ds" ]; then
    bad "não consegui criar datastore descartável"
  else
    ok "datastore descartável criado: $ds"
    assert_run "mutating add-source.sh (com verificação de indexação)" "" 0 ./datastore-add/scripts/add-source.sh "$K" "$ds" --text "O prazo de garantia é de 12 meses." --name "smoke-$ts.md" --tags smoke,teste --custom-id smoke-tenant
    assert_run "mutating query-base.sh" "" 0 ./datastore-add/scripts/query-base.sh "$K" "$ds" "garantia" --top-k 1
    assert_run "mutating list-sources.sh --tag" "" 0 ./datastore-add/scripts/list-sources.sh "$K" "$ds" --tag smoke
    assert_run "mutating datastore-tags/list-tags.sh" "" 0 ./datastore-tags/scripts/list-tags.sh "$K" "$ds"
    assert_run "mutating datastore-tags/query-verify.sh (custom_ids)" "" 0 ./datastore-tags/scripts/query-verify.sh "$K" "$ds" "garantia" --custom-id smoke-tenant
    CV_YES=1 ./datastore-add/scripts/delete-datastore.sh "$K" "$ds" >/dev/null 2>&1 && ok "datastore descartável removido ($ds)" || bad "falha ao remover datastore $ds"
  fi

  # Mutações no agente: só com um agente DEDICADO (a cota da organização pode
  # impedir criar agente novo — POST /agents responde 402 USAGE_LIMIT).
  local A="${CHATVOLT_SMOKE_AGENT_ID:-}"
  if [ -z "$A" ]; then
    skip "mutações de agente (defina CHATVOLT_SMOKE_AGENT_ID com um agente dedicado; a organização pode estar com cota de agentes esgotada)"
    return 0
  fi
  local before_temp before_model before_prompt
  before_temp=$(./prompt-adjust/scripts/get-agent.sh "$K" "$A" 2>/dev/null | grep -oE 'Temp[^0-9]*[0-9.]+' | grep -oE '[0-9.]+$' || true)
  before_model=$(./prompt-adjust/scripts/get-agent.sh "$K" "$A" 2>/dev/null | grep -oE 'Model[^ ]* +[a-z0-9_]+' | awk '{print $NF}' || true)
  before_prompt=$(./prompt-adjust/scripts/get-agent.sh "$K" "$A" 2>/dev/null | grep -c . || true)

  assert_run "mutating update-temperature.sh" "" 0 ./prompt-adjust/scripts/update-temperature.sh "$K" "$A" 0.4
  assert_run "mutating update-prompt.sh" "" 0 ./prompt-adjust/scripts/update-prompt.sh "$K" "$A" --text "Você é um agente de smoke test. Responda de forma curta."
  assert_run "mutating send-query.sh" "" 0 ./agent-test/scripts/send-query.sh "$K" "$A" "responda ok"

  if [ -n "$before_temp" ]; then
    ./prompt-adjust/scripts/update-temperature.sh "$K" "$A" "$before_temp" >/dev/null 2>&1 && ok "temperatura restaurada ($before_temp)" || bad "falha ao restaurar temperatura ($before_temp)"
  fi
  if [ -n "$before_model" ]; then
    ./prompt-adjust/scripts/update-model.sh "$K" "$A" "$before_model" >/dev/null 2>&1 && ok "modelo restaurado ($before_model)" || bad "falha ao restaurar modelo ($before_model)"
  fi
  cv_info "System prompt alterado no agente $A — revise com 'prompt-adjust/scripts/get-agent.sh' se ele não for dedicado."
}

# ── Probe ────────────────────────────────────────────────────────────────
probe() {
  local K="${CHATVOLT_API_KEY:-}"
  head_ "probe: gravando respostas cruas"
  if [ -z "$K" ]; then skip "sem CHATVOLT_API_KEY"; return 0; fi
  mkdir -p tests/probe
  local out="tests/probe/latest.json" A="${CHATVOLT_AGENT_ID:-}" DS="${CHATVOLT_DATASTORE_ID:-}"
  python3 - "$K" "$A" "$DS" "$out" <<'PY'
import json, sys, urllib.request, urllib.error
key, agent, ds, out = sys.argv[1:5]
B = "https://api.chatvolt.ai"

def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(B + path, data=data, method=method,
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")

probes = [("GET", "/agents", None), ("GET", "/agents/models", None), ("GET", "/conversation?limit=1", None)]
if agent:
    probes += [("GET", f"/agents/{agent}", None), ("GET", f"/agents/{agent}/tools", None)]
probes += [("GET", "/datastores/list", None)]
if ds:
    probes += [("GET", f"/datasources/list?datastoreId={ds}&limit=1", None)]

result = {}
for method, path, body in probes:
    status, payload = call(method, path, body)
    shape = type(payload).__name__
    keys = list(payload.keys())[:12] if isinstance(payload, dict) else None
    result[path] = {"status": status, "shape": shape, "keys": keys, "sample": json.dumps(payload, ensure_ascii=False)[:400]}
    print(f"  {status} {method:4} {path:50} {shape} {keys or ''}")
with open(out, "w") as fh:
    json.dump(result, fh, indent=2, ensure_ascii=False)
print(f"\n  salvo em {out}")
PY
}

# ── Execução ─────────────────────────────────────────────────────────────
case "$MODE" in
  --lint) lint ;;
  --stub) lint; stub_start; trap stub_stop EXIT; stub_tests ;;
  --live) lint; live_tests; [ "$MUTATING" = "1" ] && mutating_tests ;;
  --probe) probe ;;
  --all) lint; stub_start; trap stub_stop EXIT; stub_tests; stub_stop; trap - EXIT; live_tests; [ "$MUTATING" = "1" ] && mutating_tests ;;
esac

printf '\n\033[1m== resumo\033[0m\n  PASS=%s FAIL=%s SKIP=%s\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
