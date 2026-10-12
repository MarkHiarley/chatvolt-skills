#!/usr/bin/env bash
# set-tags.sh — define as etiquetas (config.tags) e/ou o custom_id de uma fonte.
#
# Mecanismo (verificado ao vivo, SOURCES.md §4):
#   * as etiquetas vivem em config.tags da FONTE (a base não tem etiquetas);
#   * não existe PATCH/PUT de fonte: ambos respondem 404 "not found";
#   * alterar metadados = UPSERT POST /datasources com id + type + datastoreId + name;
#   * isUpdateText:true SEM datasourceText  → 400 INVALID_REQUEST;
#   * sem isUpdateText e sem datasourceText → 400 INVALID_REQUEST;
#   * isUpdateText:false SEM datasourceText → 200: metadados mudam e o texto
#     indexado é preservado (textSize/nbChunks inalterados).
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

usage() {
  cat <<'EOF'
Uso: set-tags.sh <api-key> <datastore-id> <source-id>
     [--tags <a,b> | --clear-tags] [--custom-id <valor> | --clear-custom-id]
     [--text-file <arquivo> | --text "<conteúdo>"] [--yes]

Define as etiquetas (metadado local) e/ou o custom_id (filtro real de
recuperação) de UMA fonte. Como não existe PATCH de fonte (PATCH/PUT → 404), a
alteração é um UPSERT em POST /datasources com id + type + datastoreId + name.

O QUE A API FAZ COM UM `id` EXISTENTE (verificado ao vivo):
  * atualiza o `config` (tags, custom_id) — sempre;
  * o `datasourceText` enviado é ACEITO (HTTP 200) mas NÃO substitui o conteúdo
    já indexado: textSize/nbChunks e os trechos devolvidos pela query continuam
    sendo os antigos (verificado com isUpdateText no top-level e em config);
  * `isUpdateText:false` sem `datasourceText` → 200 (é o caminho dos metadados);
  * `isUpdateText:true` sem `datasourceText` → 400 INVALID_REQUEST;
  * sem `isUpdateText` e sem `datasourceText` → 400 INVALID_REQUEST.
  Para trocar o conteúdo de uma fonte existente: apague e recrie a fonte
  (skill chatvolt-datastore-add).

Modo de texto (OPCIONAL — o padrão NÃO reenvia texto):
  --reuse-text           não reenvia texto (isUpdateText:false). Só os metadados
                         mudam; o conteúdo indexado fica intacto. É o modo
                         recomendado para trocar etiquetas/custom_id.
  --text-file <arquivo>  reenvia o texto do arquivo. Aceito pela API, mas em
                         fonte existente o conteúdo indexado NÃO é substituído:
                         o script confere textSize antes/depois, avisa e sai 1
                         quando a substituição não acontece.
  --text "<conteúdo>"    idem, com o conteúdo literal na linha de comando.

Opções:
  --tags <a,b>           etiquetas finais (substitui a lista atual; vazio limpa)
  --clear-tags           remove todas as etiquetas
  --custom-id <valor>    define config.custom_id (filtro multi-tenant)
  --clear-custom-id      remove o custom_id
  --yes                  não pede confirmação (equivalente a CV_YES=1)
  -h, --help             Mostra esta ajuda

Exemplos:
  set-tags.sh "$CHATVOLT_API_KEY" <base> <fonte> --tags a,b --reuse-text
  set-tags.sh "$CHATVOLT_API_KEY" <base> <fonte> --clear-tags --reuse-text
  set-custom-id.sh "$CHATVOLT_API_KEY" <base> <fonte> tenant-x --reuse-text
  set-tags.sh "$CHATVOLT_API_KEY" <base> <fonte> --tags novo --text-file doc.md

Saída (CV_JSON=1): {"datastoreId","sourceId","name","textMode","textBytes",
  "textSent","textApplied","before":{tags,custom_id,status,nbChunks,textSize,hash},
  "after":{…},"isUpdateText","status","nbChunks","tagsChanged","customIdChanged",
  "warnings":[…]}
  "textApplied" só é true no modo --reuse-text (o conteúdo é preservado por
  construção); nos modos com texto ele indica se o textSize mudou de fato.

Exit: 0 ok · 1 erro de cliente (inclui texto não substituído) · 3 quota (402) ·
      4 rede · 5 servidor · 130 cancelado
EOF
}

# cv_get_source <datastore-id> <source-id> <arquivo-saída> — GET da fonte.
cv_get_source() {
  local ds="$1" sid="$2" out="$3"
  cv_get "/datasources/${sid}?idstore=${ds}"
  printf '%s' "$CV_RESP" >"$out"
}

# cv_wait_synched <datastore-id> <source-id> <arquivo-saída> <nbSynch-mínimo>
# Espera a reindexação: o status volta a `synched` com nbChunks > 0 E o nbSynch
# precisa avançar — sem isso um GET imediatamente após o POST devolveria o
# estado antigo (ainda `synched`) e daríamos a reindexação por concluída.
cv_wait_synched() {
  local ds="$1" sid="$2" out="$3" min_ns="$4" deadline=$((SECONDS + 90)) st chunks ns
  while :; do
    cv_get_source "$ds" "$sid" "$out"
    read -r st chunks ns <<<"$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("status") or "", d.get("nbChunks") or 0, d.get("nbSynch") or 0)' "$out")"
    [ "$st" = "error" ] && cv_die "a indexação falhou (status=error) — inspecione com show-source-tags.sh"
    if [ "$st" = "synched" ] && [ "$chunks" -gt 0 ] && [ "$ns" -gt "$min_ns" ]; then return 0; fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      cv_warn "timeout de 90s aguardando a reindexação (status=${st}, nbChunks=${chunks}, nbSynch=${ns}, esperado > ${min_ns})"
      return 1
    fi
    sleep 4
  done
}

[ $# -ge 1 ] || { usage; exit 1; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

API_KEY=$(cv_req_key "${1:-}"); shift
DS="${1:-}"; shift || true
SRC="${1:-}"; shift || true
[ -n "$DS" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$SRC" ] || { usage >&2; cv_die "informe o <source-id>"; }

TAGS_SET=0; TAGS=""
TEXT_MODE=""; TEXT_FILE=""; TEXT_LIT=""
CUSTOM_SET=0; CUSTOM=""

while [ $# -gt 0 ]; do
  case "$1" in
    --tags)        TAGS="${2:-}"; TAGS_SET=1; shift 2 ;;
    --clear-tags)  TAGS=""; TAGS_SET=1; shift ;;
    --text-file)   [ -n "${2:-}" ] || cv_die "--text-file exige o caminho do arquivo"
                   [ -z "$TEXT_MODE" ] || cv_die "escolha apenas um modo de texto (--reuse-text, --text-file, --text)"
                   TEXT_FILE="$2"; TEXT_MODE=file; shift 2 ;;
    --text)        [ -n "${2:-}" ] || cv_die "--text exige o conteúdo"
                   [ -z "$TEXT_MODE" ] || cv_die "escolha apenas um modo de texto (--reuse-text, --text-file, --text)"
                   TEXT_LIT="$2"; TEXT_MODE=literal; shift 2 ;;
    --reuse-text)  [ -z "$TEXT_MODE" ] || cv_die "escolha apenas um modo de texto (--reuse-text, --text-file, --text)"
                   TEXT_MODE=reuse; shift ;;
    --custom-id)   CUSTOM="${2:-}"; CUSTOM_SET=1; shift 2 ;;
    --clear-custom-id) CUSTOM=""; CUSTOM_SET=1; shift ;;
    --yes)         CV_YES=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

[ -n "$TEXT_MODE" ] || TEXT_MODE="reuse"   # padrão: só metadados (isUpdateText=false)
{ [ "$TAGS_SET" = 1 ] || [ "$CUSTOM_SET" = 1 ]; } || cv_die "informe --tags/--clear-tags e/ou --custom-id/--clear-custom-id"
if [ "$TEXT_MODE" = "file" ]; then
  [ -f "$TEXT_FILE" ] || cv_die "arquivo não encontrado: $TEXT_FILE"
  [ -r "$TEXT_FILE" ] || cv_die "arquivo sem permissão de leitura: $TEXT_FILE"
fi

TAGS_JSON=$(printf '%s' "$TAGS" | python3 -c 'import json,sys
raw = sys.stdin.read()
out = []
for part in raw.split(","):
    t = part.strip()
    if t and t not in out:
        out.append(t)
print(json.dumps(out, ensure_ascii=False))')

TMPD="$(mktemp -d)" || cv_die "não foi possível criar diretório temporário"
trap 'rm -rf "$TMPD"' EXIT
BEFORE="$TMPD/before.json"
AFTER="$TMPD/after.json"
PAYLOAD="$TMPD/payload.json"

cv_get_source "$DS" "$SRC" "$BEFORE"

BEFORE_NS=$(python3 -c 'import json,sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("nbSynch") or 0)' "$BEFORE")

python3 -c 'import json,sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
if d.get("datastoreId") != sys.argv[2]:
    sys.stderr.write("ERRO: a fonte %s pertence à base %s, não a %s — confira os IDs\n"
                     % (d.get("id"), d.get("datastoreId"), sys.argv[2]))
    raise SystemExit(1)' "$BEFORE" "$DS"

SUMMARY=$(python3 - "$BEFORE" "$DS" "$TAGS_SET" "$TAGS_JSON" "$TEXT_MODE" "$TEXT_FILE" "$TEXT_LIT" \
                     "$CUSTOM_SET" "$CUSTOM" "$PAYLOAD" <<'PY'
import json, sys

before_path, ds, tags_set, tags_json, mode, text_file, text_lit, custom_set, custom, out_path = sys.argv[1:11]

with open(before_path, encoding="utf-8") as fh:
    src = json.load(fh)
cfg = dict(src.get("config") or {})

payload = {
    "id": src.get("id"),
    "type": src.get("type") or "file",
    "datastoreId": ds,
    "name": src.get("name") or "",
}
text_bytes = None
if mode == "file":
    try:
        with open(text_file, encoding="utf-8") as fh:
            content = fh.read()
    except UnicodeDecodeError:
        sys.stderr.write("ERRO: %s não é texto UTF-8 — extraia o texto (ex.: pdftotext) e reenvie como .txt/.md\n" % text_file)
        raise SystemExit(1)
    payload["datasourceText"] = content
    payload["isUpdateText"] = True
    text_bytes = len(content.encode("utf-8"))
elif mode == "literal":
    payload["datasourceText"] = text_lit
    payload["isUpdateText"] = True
    text_bytes = len(text_lit.encode("utf-8"))
else:
    payload["isUpdateText"] = False

if tags_set == "1":
    cfg["tags"] = json.loads(tags_json)
if custom_set == "1":
    cfg["custom_id"] = custom
payload["config"] = cfg

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False)

print(json.dumps({"textBytes": text_bytes, "tags": cfg.get("tags") or [],
                  "customId": cfg.get("custom_id") or "", "isUpdateText": payload["isUpdateText"]},
                 ensure_ascii=False))
PY
)

if [ "$TEXT_MODE" != "reuse" ]; then
  TB=$(printf '%s' "$SUMMARY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["textBytes"] or 0)')
  [ "$TB" -gt 0 ] || cv_die "o texto enviado está vazio — isso zeraria o conteúdo indexado da fonte"
fi

BLOCK=$(python3 - "$BEFORE" "$SUMMARY" "$TEXT_MODE" <<'PY'
import json, sys

src = json.load(open(sys.argv[1], encoding="utf-8"))
summ = json.loads(sys.argv[2])
mode = sys.argv[3]
cfg = src.get("config") or {}
bt = [str(t) for t in (cfg.get("tags") or [])]

lines = []
lines.append("Fonte:  %s (%s) · base %s" % (src.get("name"), src.get("id"), src.get("datastoreId")))
lines.append("Antes:  tags [%s] · custom_id %s · status %s · nbChunks %s · textSize %s B"
             % (", ".join(bt) if bt else "-", cfg.get("custom_id") or "-", src.get("status"),
                src.get("nbChunks"), src.get("textSize")))
lines.append("Depois: tags [%s] · custom_id %s"
             % (", ".join(summ["tags"]) if summ["tags"] else "-", summ["customId"] or "-"))
if mode == "reuse":
    lines.append("Texto:  NÃO reenviado (isUpdateText=false) — o conteúdo indexado é preservado")
else:
    lines.append("Texto:  reenviado, %s bytes (isUpdateText=true) — ATENÇÃO: em fonte existente a API"
                 % summ["textBytes"])
    lines.append("        aceita este texto mas NÃO substitui o conteúdo indexado; o script confere depois")
lines.append("HTTP:   POST /datasources (upsert; não existe PATCH/PUT de fonte)")
print("\n".join(lines))
PY
)

cv_info "$BLOCK"
cv_confirm "Aplicar este upsert em POST /datasources?"

PAYLOAD_BODY="$(cat -- "$PAYLOAD")"
cv_request POST "/datasources" "$PAYLOAD_BODY"

if [ "$TEXT_MODE" = "reuse" ]; then
  sleep 1
  cv_get_source "$DS" "$SRC" "$AFTER"
else
  cv_info "aguardando a reindexação da fonte (nbSynch precisa avançar)…"
  cv_wait_synched "$DS" "$SRC" "$AFTER" "$BEFORE_NS" || cv_die "a fonte não voltou a status=synched com nbChunks>0 e nbSynch avançado — inspecione com show-source-tags.sh"
fi

RESULT=$(python3 - "$BEFORE" "$AFTER" "$TEXT_MODE" "$SUMMARY" <<'PY'
import json, sys

before = json.load(open(sys.argv[1], encoding="utf-8"))
after = json.load(open(sys.argv[2], encoding="utf-8"))
mode = sys.argv[3]
summ = json.loads(sys.argv[4])
bc = before.get("config") or {}
ac = after.get("config") or {}

bt = [str(t) for t in (bc.get("tags") or [])]
at = [str(t) for t in (ac.get("tags") or [])]
expect_tags = [str(t) for t in summ["tags"]]
warnings = []
if at != expect_tags:
    warnings.append("o GET devolveu as etiquetas %s, diferente do enviado %s" % (at, expect_tags))
if mode == "reuse":
    if before.get("textSize") != after.get("textSize") or before.get("nbChunks") != after.get("nbChunks"):
        warnings.append("texto indexado mudou sem reenvio (textSize/nbChunks %s/%s → %s/%s)"
                        % (before.get("textSize"), before.get("nbChunks"), after.get("textSize"), after.get("nbChunks")))
    if before.get("hash") != after.get("hash"):
        warnings.append("hash do conteúdo mudou (a API reindexa a cada upsert) — confirme com query-verify.sh")
else:
    if before.get("textSize") == after.get("textSize") and before.get("nbChunks") == after.get("nbChunks"):
        warnings.append("a API aceitou o texto enviado mas NÃO substituiu o conteúdo indexado "
                        "(textSize %s B e nbChunks %s continuam iguais): em fonte existente o POST /datasources "
                        "atualiza apenas o config. As etiquetas/custom_id foram aplicados. Para trocar o "
                        "conteúdo, apague a fonte e recrie (skill chatvolt-datastore-add)."
                        % (after.get("textSize"), after.get("nbChunks")))

def snap(d):
    c = d.get("config") or {}
    return {"tags": [str(t) for t in (c.get("tags") or [])], "custom_id": c.get("custom_id") or None,
            "status": d.get("status"), "nbChunks": d.get("nbChunks"), "textSize": d.get("textSize"),
            "hash": d.get("hash")}

text_sent = mode != "reuse"
# --reuse-text preserva o conteúdo por construção; nos modos com texto o único
# sinal confiável (sem endpoint que devolva o texto armazenado) é o textSize.
text_applied = True if not text_sent else (before.get("textSize") != after.get("textSize"))

res = {"datastoreId": after.get("datastoreId"), "sourceId": after.get("id"), "name": after.get("name"),
       "textMode": mode, "textBytes": summ["textBytes"], "textSent": text_sent, "textApplied": text_applied,
       "isUpdateText": summ["isUpdateText"],
       "before": snap(before), "after": snap(after), "status": after.get("status"),
       "nbChunks": after.get("nbChunks"),
       "tagsChanged": sorted(bt) != sorted(at), "customIdChanged": (bc.get("custom_id") or None) != (ac.get("custom_id") or None),
       "warnings": warnings}
print(json.dumps(res, ensure_ascii=False))
PY
)

if [ "$CV_JSON" = "1" ]; then
  cv_emit "$RESULT"
else
  printf '%s' "$RESULT" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("")
print("OK — fonte %s atualizada" % d["sourceId"])
print("  etiquetas: [%s] → [%s]%s" % (", ".join(d["before"]["tags"]) or "-", ", ".join(d["after"]["tags"]) or "-",
                                     "  ✅" if d["tagsChanged"] else "  (inalteradas)"))
print("  custom_id: %s → %s%s" % (d["before"]["custom_id"] or "-", d["after"]["custom_id"] or "-",
                                   "  ✅" if d["customIdChanged"] else "  (inalterado)"))
print("  indexação: status %s · nbChunks %s · textSize %s B" % (d["status"], d["nbChunks"], d["after"]["textSize"]))
if not d["textSent"]:
    print("  texto:     não reenviado (--reuse-text): o conteúdo indexado continua o mesmo")
elif d["textApplied"]:
    print("  texto:     %s bytes reenviados e o textSize mudou ✅" % d["textBytes"])
else:
    print("  texto:     %s bytes reenviados, mas o conteúdo indexado NÃO mudou ❌" % d["textBytes"])
for w in d["warnings"]:
    print("  AVISO: " + w)
print("")
print("Prove a recuperação com: query-verify.sh <api-key> " + str(d["datastoreId"]) + " \"<pergunta>\" [--custom-id <valor>]")
'
fi

# Modo texto: se a API não substituiu o conteúdo, o pedido não foi cumprido —
# sai 1 mesmo com as etiquetas aplicadas (o JSON já saiu no stdout).
if [ "$TEXT_MODE" != "reuse" ]; then
  APPLIED=$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print("1" if json.load(sys.stdin)["textApplied"] else "0")')
  [ "$APPLIED" = "1" ] || cv_die "o conteúdo indexado não foi substituído (as etiquetas/custom_id foram aplicados) — para trocar o conteúdo, apague a fonte e recrie com a skill chatvolt-datastore-add"
fi
