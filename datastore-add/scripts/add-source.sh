#!/usr/bin/env bash
set -euo pipefail

# Chatvolt — Adicionar (ou substituir) uma fonte de conteúdo em uma base de conhecimento.
# Contrato HTTP: SOURCES.md na raiz do repo.
#
# Caminho confiável: POST /datasources com JSON + datasourceText (o servidor indexa
# o texto e cria os chunks). O upload multipart grava o arquivo como binário, NÃO
# indexa (nbChunks=0) e é justamente o que este script evita.

usage() {
  cat <<'EOF'
Uso: ./add-source.sh <api-key> <datastore-id> (conteúdo) [opções]

Adiciona uma fonte à base de conhecimento e VERIFICA a indexação.

Conteúdo (escolha exatamente um):
  --text <texto>            envia o texto direto (type=file)
  --text-file <arquivo>     lê um arquivo de texto (type=file)
  --file <arquivo>          arquivo de texto (.md/.txt/.csv/...) ou PDF (extrai com pdftotext)
  --qa "pergunta::resposta" envia um par pergunta/resposta (type=qa)
  --url <url> [--site]      fonte web: web_page (ou web_site com --site, que rastreia o site)

Metadados:
  --name <nome>             nome da fonte (padrão: derivado do conteúdo/arquivo)
  --tags a,b                etiquetas (config.tags) — defina-as na criação; para
                            alterar depois use a skill chatvolt-datastore-tags
  --custom-id <id>          identificador de filtro (config.custom_id), usado em
                            filters.custom_ids na consulta (multi-tenant)

Upsert:
  --update <source-id>      atualiza uma fonte existente (POST /datasources com "id"):
                            reenvia o conteúdo e reaproveita nome/tags/custom_id atuais
                            quando não informados. (pede confirmação; CV_YES=1 pula)
                            ATENÇÃO (verificado ao vivo em 2026-10-12): a API atualiza o
                            registro da fonte (nome/tamanho/nbSynch) mas NÃO reindexa o
                            conteúdo — os chunks continuam com o texto anterior. Para
                            TROCAR o conteúdo use delete-source.sh e reenvie.

Verificação de indexação (sempre depois de enviar):
  --query <texto>           pergunta de prova usada na consulta (padrão: derivada do texto)
  --timeout <segundos>      tempo máximo de espera pelo status "synched" (padrão 90)
  --no-verify               NÃO verifica (só para depuração/stub offline) — desaconselhado
  -h, --help                mostra esta ajuda

A verificação exige: status == "synched" E nbChunks > 0 E a consulta de prova
retornar ao menos um trecho. Se qualquer um desses falhar, o script termina com
código 1 e mostra como remover a fonte. Quando os trechos retornados não contêm os
termos do texto enviado (menos de 50% dos termos significativos), o script apenas
avisa — é o sintoma do upsert que não reindexa. Para fontes --url (conteúdo buscado
pelo servidor), a consulta de prova é informativa.

Exemplos:
  ./add-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 --text-file manual.md
  ./add-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 --file politica.pdf --tags "politica,2027"
  ./add-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 --qa "Qual o prazo?::São 30 dias."
  ./add-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 --url https://exemplo.com/faq
  CV_JSON=1 ./add-source.sh "$CHATVOLT_API_KEY" cmabc123_v3 --text "conteúdo de prova"

Variáveis: CV_JSON=1 (stdout somente JSON) · CV_YES=1 (pula confirmação) ·
           CV_POLL_INTERVAL=<s> (padrão 3) · CV_API_BASE=<url> (stub offline)
EOF
}

source "$(dirname "$0")/_lib.sh"

KIND=""
ARG=""
SITE=0
NAME=""
TAGS=""
CUSTOM_ID=""
UPDATE_ID=""
PROOF_QUERY=""
TIMEOUT=90
VERIFY=1
POS=()

set_kind() {
  [ -z "$KIND" ] || cv_die "informe apenas um tipo de conteúdo (já definido: --${KIND})"
  KIND="$1"
  ARG="$2"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --text) [ "$#" -ge 2 ] || { echo "ERRO: --text exige um valor" >&2; exit 1; }; set_kind text "$2"; shift 2 ;;
    --text-file) [ "$#" -ge 2 ] || { echo "ERRO: --text-file exige um valor" >&2; exit 1; }; set_kind text-file "$2"; shift 2 ;;
    --file) [ "$#" -ge 2 ] || { echo "ERRO: --file exige um valor" >&2; exit 1; }; set_kind file "$2"; shift 2 ;;
    --qa) [ "$#" -ge 2 ] || { echo "ERRO: --qa exige um valor" >&2; exit 1; }; set_kind qa "$2"; shift 2 ;;
    --url) [ "$#" -ge 2 ] || { echo "ERRO: --url exige um valor" >&2; exit 1; }; set_kind url "$2"; shift 2 ;;
    --site) SITE=1; shift ;;
    --name) [ "$#" -ge 2 ] || { echo "ERRO: --name exige um valor" >&2; exit 1; }; NAME="$2"; shift 2 ;;
    --tags) [ "$#" -ge 2 ] || { echo "ERRO: --tags exige um valor" >&2; exit 1; }; TAGS="$2"; shift 2 ;;
    --custom-id) [ "$#" -ge 2 ] || { echo "ERRO: --custom-id exige um valor" >&2; exit 1; }; CUSTOM_ID="$2"; shift 2 ;;
    --update) [ "$#" -ge 2 ] || { echo "ERRO: --update exige um valor" >&2; exit 1; }; UPDATE_ID="$2"; shift 2 ;;
    --query) [ "$#" -ge 2 ] || { echo "ERRO: --query exige um valor" >&2; exit 1; }; PROOF_QUERY="$2"; shift 2 ;;
    --timeout) [ "$#" -ge 2 ] || { echo "ERRO: --timeout exige um valor" >&2; exit 1; }; TIMEOUT="$2"; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do POS+=("$1"); shift; done ;;
    -*) echo "ERRO: opção desconhecida: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done

API_KEY=$(cv_req_key "${POS[0]:-}")
DS_ID="${POS[1]:-}"
[ -n "$DS_ID" ] || { usage >&2; cv_die "informe o <datastore-id>"; }
[ -n "$KIND" ] || { usage >&2; cv_die "informe o conteúdo (--text/--text-file/--file/--qa/--url)"; }
case "$TIMEOUT" in ''|*[!0-9]*) cv_die "--timeout deve ser um número inteiro de segundos" ;; esac

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

mime_for() {
  case "${1,,}" in
    *.md|*.markdown) echo "text/markdown" ;;
    *.csv|*.tsv) echo "text/csv" ;;
    *.json|*.jsonl) echo "application/json" ;;
    *.html|*.htm) echo "text/html" ;;
    *.xml) echo "application/xml" ;;
    *.yaml|*.yml) echo "text/yaml" ;;
    *) echo "text/plain" ;;
  esac
}

is_text_ext() {
  case "${1,,}" in
    *.txt|*.md|*.markdown|*.csv|*.tsv|*.json|*.jsonl|*.html|*.htm|*.xml|*.yaml|*.yml|*.log|*.sql|*.ini|*.conf|*.toml|*.rst|*.tex|*.mdx|*.srt|*.vtt) return 0 ;;
    *) return 1 ;;
  esac
}

TEXT_FILE=""
TYPE=""
SOURCE_URL=""
QUESTION=""
ANSWER=""
MIME="text/plain"

case "$KIND" in
  text-file)
    [ -f "$ARG" ] || cv_die "arquivo não encontrado: $ARG"
    cp -- "$ARG" "$TMPD/text"
    TEXT_FILE="$TMPD/text"
    MIME=$(mime_for "$ARG")
    [ -n "$NAME" ] || NAME=$(basename -- "$ARG")
    TYPE="file"
    ;;
  text)
    [ -n "$ARG" ] || cv_die "--text exige um texto não vazio"
    printf '%s' "$ARG" > "$TMPD/text"
    TEXT_FILE="$TMPD/text"
    MIME="text/plain"
    TYPE="file"
    ;;
  qa)
    case "$ARG" in
      *"::"*) : ;;
      *) cv_die '--qa espera "pergunta::resposta" (use :: entre a pergunta e a resposta)' ;;
    esac
    QUESTION="${ARG%%::*}"
    ANSWER="${ARG#*::}"
    [ -n "$QUESTION" ] || cv_die "--qa: a pergunta está vazia"
    [ -n "$ANSWER" ] || cv_die "--qa: a resposta está vazia"
    printf 'Pergunta: %s\nResposta: %s\n' "$QUESTION" "$ANSWER" > "$TMPD/text"
    TEXT_FILE="$TMPD/text"
    MIME="text/plain"
    TYPE="qa"
    ;;
  url)
    case "$ARG" in
      http://*|https://*) : ;;
      *) cv_die "--url espera uma URL http(s) (recebido: $ARG)" ;;
    esac
    SOURCE_URL="$ARG"
    TYPE="web_page"
    [ "$SITE" = "1" ] && TYPE="web_site"
    if [ -z "$NAME" ]; then
      NAME=$(python3 -c '
import sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
leaf = u.path.rstrip("/").rsplit("/", 1)[-1]
print(urllib.parse.unquote(leaf) if leaf else (u.netloc or sys.argv[1]))
' "$ARG")
    fi
    ;;
  file)
    [ -f "$ARG" ] || cv_die "arquivo não encontrado: $ARG"
    case "${ARG,,}" in
      *.pdf)
        if command -v pdftotext >/dev/null 2>&1; then
          cv_info "Extraindo texto de ${ARG} com pdftotext..."
          pdftotext -layout -- "$ARG" "$TMPD/text" || cv_die "pdftotext falhou em $ARG"
          bytes=$(wc -c < "$TMPD/text")
          [ "$bytes" -ge 50 ] || cv_die "pdftotext extraiu ${bytes} byte(s) de $ARG: provavelmente é um PDF digitalizado (imagem). Rode OCR antes (ex.: ocrmypdf) ou envie o texto com --text-file"
          TEXT_FILE="$TMPD/text"
        else
          cv_die "arquivo PDF e o extrator 'pdftotext' não está instalado. Instale poppler-utils (ex.: sudo pacman -S poppler) ou converta antes (pdftotext/libreoffice/pandoc) e use --text-file. Upload multipart NÃO é usado por este script: o servidor grava o binário e indexa 0 chunks"
        fi
        ;;
      *.docx|*.doc|*.odt|*.xlsx|*.xls|*.pptx|*.ppt)
        cv_die "formato binário (${ARG##*.}) não é indexável por texto. Converta antes (libreoffice --headless --convert-to txt --outdir /tmp \"$ARG\") e use --text-file"
        ;;
      *)
        if is_text_ext "$ARG"; then
          cp -- "$ARG" "$TMPD/text"
        else
          kind=$(python3 - "$ARG" <<'PY'
import sys
with open(sys.argv[1], "rb") as fh:
    head = fh.read(8192)
if b"\x00" in head:
    print("binary")
else:
    try:
        head.decode("utf-8")
        print("text")
    except UnicodeDecodeError:
        print("binary")
PY
)
          if [ "$kind" = "binary" ]; then
            cv_die "$(basename -- "$ARG") parece ser binário (extensão '${ARG##*.}' desconhecida) e não há extrator para ele. Converta para texto e use --text-file (PDFs: pdftotext). Este script não faz upload multipart: o servidor grava o binário e indexa 0 chunks"
          fi
          cv_warn "extensão '${ARG##*.}' não reconhecida; o conteúdo parece texto — enviando como texto puro"
          cp -- "$ARG" "$TMPD/text"
        fi
        MIME=$(mime_for "$ARG")
        TEXT_FILE="$TMPD/text"
        ;;
    esac
    [ -n "$NAME" ] || NAME=$(basename -- "$ARG")
    TYPE="file"
    ;;
esac

if [ -n "$TEXT_FILE" ]; then
  nbytes=$(wc -c < "$TEXT_FILE")
  [ "$nbytes" -gt 0 ] || cv_die "conteúdo vazio: nada para indexar"
  [ "$nbytes" -le 950000 ] || cv_die "texto com ${nbytes} bytes; o limite de payload da API é 1 MB — divida o conteúdo em mais de uma fonte"
fi

if [ -z "$NAME" ]; then
  if [ -n "$QUESTION" ]; then
    NAME=$(python3 -c 'import sys; print(" ".join(sys.argv[1].split())[:60] or "pergunta")' "$QUESTION")
  elif [ -n "$TEXT_FILE" ]; then
    NAME=$(python3 - "$TEXT_FILE" <<'PY'
import re, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    text = fh.read()

name = ""
for line in text.splitlines():
    line = re.sub(r"^[\s>#*\-]+", "", line).strip()
    if line:
        name = line
        break
print(" ".join(name.split())[:60] or "texto")
PY
)
  else
    NAME="fonte-web"
  fi
fi

# --- upsert: reaproveita metadados atuais quando não informados -------------
if [ -n "$UPDATE_ID" ]; then
  cv_get "/datasources/${UPDATE_ID}?idstore=${DS_ID}"
  CUR="$CV_RESP"
  IFS=$'\x1f' read -r CUR_NAME CUR_TAGS CUR_CUSTOM CUR_DS < <(python3 - "$CUR" <<'PY'
import json, sys

d = json.loads(sys.argv[1])
cfg = d.get("config") or {}
sep = "\x1f"
print(sep.join([d.get("name") or "", ",".join(cfg.get("tags") or []),
                cfg.get("custom_id") or "", d.get("datastoreId") or ""]))
PY
)
  [ "$CUR_DS" = "$DS_ID" ] || cv_die "a fonte ${UPDATE_ID} pertence ao datastore ${CUR_DS}, não a ${DS_ID}"
  [ -n "$NAME" ] || NAME="$CUR_NAME"
  [ -n "$TAGS" ] || TAGS="$CUR_TAGS"
  [ -n "$CUSTOM_ID" ] || CUSTOM_ID="$CUR_CUSTOM"
  cv_warn "--update ${UPDATE_ID}: o registro desta fonte será reescrito com o texto enviado"
  cv_warn "   (observado: a API atualiza o registro mas NÃO reindexa os chunks — o script confere e avisa)"
  cv_warn "   nome: ${NAME}   tags: ${TAGS:--}   custom_id: ${CUSTOM_ID:--}"
  cv_confirm "Substituir o conteúdo da fonte ${UPDATE_ID} em ${DS_ID}?"
fi

# --- payload ---------------------------------------------------------------
BODY=$(python3 - "$DS_ID" "$TYPE" "$NAME" "$TAGS" "$CUSTOM_ID" "$SOURCE_URL" "$QUESTION" "$ANSWER" "$TEXT_FILE" "$MIME" "$UPDATE_ID" <<'PY'
import json, sys

(ds, typ, name, tags_csv, custom_id, source_url,
 question, answer, text_path, mime, update_id) = sys.argv[1:12]

cfg = {}
tags = [t.strip() for t in tags_csv.split(",") if t.strip()]
if tags:
    cfg["tags"] = tags
if custom_id:
    cfg["custom_id"] = custom_id
if source_url:
    cfg["source_url"] = source_url
if question:
    cfg["question"] = question
if answer:
    cfg["answer"] = answer

body = {"type": typ, "datastoreId": ds, "name": name}
if update_id:
    body["id"] = update_id

if text_path:
    with open(text_path, encoding="utf-8") as fh:
        text = fh.read()
    body["datasourceText"] = text
    body["isUpdateText"] = True
    cfg["mime_type"] = mime
    cfg["fileSize"] = len(text.encode("utf-8"))

if cfg:
    body["config"] = cfg

print(json.dumps(body, ensure_ascii=False))
PY
)

cv_info "Enviando fonte (type=${TYPE}) para ${DS_ID}..."
cv_request POST "/datasources" "$BODY"

SRC_ID=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id","") if isinstance(d,dict) else "")')
[ -n "$SRC_ID" ] || cv_die "a API não devolveu o id da fonte criada: $(cv_err_msg "$CV_RESP")"

# --- verificação de indexação ---------------------------------------------
STATUS=""
CHUNKS=""
TOKENS=""
ELAPSED=0
PROOF_HITS=""
PROOF_RATIO=""
PROOF_OK="nao-aplicavel"
FAIL=""

if [ "$VERIFY" != "1" ]; then
  cv_warn "--no-verify: a indexação NÃO foi conferida. Rode ./get-source.sh ${DS_ID} ${SRC_ID} em alguns segundos."
else
  start=$(date +%s)
  read -r STATUS CHUNKS TOKENS <<< "$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("status") or "-", d.get("nbChunks") or 0, d.get("nbTokens") or 0)
')"
  if [ "$STATUS" = "synched" ] && [ "$CHUNKS" -gt 0 ]; then
    cv_info "  status=${STATUS} nbChunks=${CHUNKS} (já indexada na resposta do POST)"
  else
    POLL="${CV_POLL_INTERVAL:-3}"
    while :; do
      cv_get "/datasources/${SRC_ID}?idstore=${DS_ID}"
      read -r STATUS CHUNKS TOKENS <<< "$(printf '%s' "$CV_RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("status") or "-", d.get("nbChunks") or 0, d.get("nbTokens") or 0)
')"
      ELAPSED=$(( $(date +%s) - start ))
      cv_info "  status=${STATUS} nbChunks=${CHUNKS} (${ELAPSED}s)"
      case "$STATUS" in
        synched) break ;;
        error|usage_limit_reached)
          FAIL="a fonte terminou com status '${STATUS}' (a API não conseguiu indexar o conteúdo)"
          break ;;
      esac
      if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        FAIL="timeout de ${TIMEOUT}s esperando status 'synched' (status atual: ${STATUS:-desconhecido})"
        break
      fi
      sleep "$POLL"
    done

    if [ -z "$FAIL" ] && [ "$CHUNKS" -le 0 ]; then
      FAIL="status='${STATUS}' mas nbChunks=0: nenhum trecho foi indexado (é o sintoma do upload binário/multipart)"
    fi
  fi
fi

# --- consulta de prova -----------------------------------------------------
if [ "$VERIFY" = "1" ] && [ -z "$FAIL" ]; then
  STRICT=1
  if [ -z "$PROOF_QUERY" ]; then
    if [ -n "$QUESTION" ]; then
      PROOF_QUERY="$QUESTION"
    elif [ -n "$TEXT_FILE" ]; then
      PROOF_QUERY=$(python3 - "$TEXT_FILE" <<'PY'
import re, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    text = fh.read()

query = ""
for line in text.splitlines():
    line = re.sub(r"^[\s>#*\-]+", "", line).strip()
    if len(line.split()) >= 3:
        query = line
        break
if not query:
    query = " ".join(text.split())
print(query[:120])
PY
)
    else
      STRICT=0
      PROOF_QUERY=""
      cv_warn "--url sem --query: não há pergunta de prova derivável do conteúdo; a verificação fica em status/nbChunks"
    fi
  fi
  TOKEN_CHECK=0
  if [ -n "$TEXT_FILE" ]; then TOKEN_CHECK=1; fi
  if [ -n "$PROOF_QUERY" ]; then
    QBODY=$(python3 - "$PROOF_QUERY" "$SRC_ID" <<'PY'
import json, sys
print(json.dumps({"query": sys.argv[1], "topK": 5,
                  "filters": {"datasource_ids": [sys.argv[2]]}}, ensure_ascii=False))
PY
)
    cv_request POST "/datastores/${DS_ID}/query" "$QBODY"
    PROOF_HITS=$(printf '%s' "$CV_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)')
    if [ "$PROOF_HITS" -le 0 ]; then
      if [ "$STRICT" = "1" ]; then
        PROOF_OK="falhou"
        FAIL="a consulta de prova não retornou trechos (a indexação não produziu conteúdo recuperável)"
      else
        PROOF_OK="informativo"
        cv_warn "a consulta de prova não retornou trechos para ${SRC_ID}"
      fi
    elif [ "$TOKEN_CHECK" = "1" ]; then
      printf '%s' "$CV_RESP" > "$TMPD/proof.json"
      read -r PROOF_RATIO PROOF_MATCH <<< "$(python3 - "$TMPD/proof.json" "$PROOF_QUERY" <<'PY'
import json, re, sys, unicodedata

chunks = json.load(open(sys.argv[1], encoding="utf-8"))
query = sys.argv[2]
if isinstance(chunks, dict):
    chunks = chunks.get("data") or []

STOP = {"de", "da", "do", "das", "dos", "e", "o", "a", "os", "as", "um", "uma", "uns", "umas",
        "para", "com", "sem", "que", "por", "sobre", "como", "mais", "menos", "no", "na", "nos",
        "nas", "em", "ao", "aos", "ou", "se", "ser", "sua", "seu", "suas", "seus", "the", "of",
        "to", "and", "for", "this", "that"}

def toks(value):
    value = unicodedata.normalize("NFKD", str(value or ""))
    value = "".join(ch for ch in value if not unicodedata.combining(ch)).lower()
    return [t for t in re.findall(r"[a-z0-9][a-z0-9._-]{2,}", value)]

wanted = [t for t in toks(query) if t not in STOP]
if len(wanted) < 2:
    print("0.00 poucos-tokens")
    raise SystemExit

pool = set()
for c in chunks:
    pool.update(toks(c.get("text")))

found = sum(1 for t in wanted if t in pool)
ratio = found / len(wanted)
print(f"{ratio:.2f} {'ok' if ratio >= 0.5 else 'degradado'}")
PY
)"
      case "$PROOF_MATCH" in
        ok|poucos-tokens) PROOF_OK="ok" ;;
        *)
          PROOF_OK="degradado"
          cv_warn "os trechos retornados não contêm o texto enviado (só ${PROOF_RATIO} dos termos significativos aparecem)."
          if [ -n "$UPDATE_ID" ]; then
            cv_warn "O registro da fonte foi atualizado, mas a API NÃO reindexou o conteúdo (comportamento observado em 2026-10-12)."
            cv_warn "Para TROCAR o conteúdo indexado: ./delete-source.sh <api-key> ${DS_ID} ${UPDATE_ID} e depois reenvie com add-source.sh."
          else
            cv_warn "A fonte está indexada (nbChunks=${CHUNKS}); confira o conteúdo com ./query-base.sh --datasource-id ${SRC_ID} ou refine a pergunta de prova com --query."
          fi
          ;;
      esac
    else
      PROOF_OK="ok"
    fi
  fi
fi

# --- saída -----------------------------------------------------------------
if [ -n "$FAIL" ]; then
  {
    echo "❌ Verificação de indexação FALHOU: ${FAIL}"
    echo "   fonte: ${NAME} (${SRC_ID}) em ${DS_ID}"
    echo "   status=${STATUS:-?} nbChunks=${CHUNKS:-?} nbTokens=${TOKENS:-?}"
    echo "   A fonte continua na base. Para remover:"
    echo "     ./delete-source.sh <api-key> ${DS_ID} ${SRC_ID}"
  } >&2
  if [ "$CV_JSON" = "1" ]; then
    python3 - "$CV_RESP" "$SRC_ID" "$STATUS" "$CHUNKS" "$TOKENS" "$PROOF_QUERY" "$PROOF_HITS" "$PROOF_OK" "$ELAPSED" "$FAIL" "$PROOF_RATIO" <<'PY'
import json, sys

(ds, sid, status, chunks, tokens, query, hits, proof, elapsed, fail, ratio) = sys.argv[1:12]
print(json.dumps({
    "datasource": json.loads(ds),
    "verification": {"status": status, "nbChunks": int(chunks or 0), "nbTokens": int(tokens or 0),
                     "proof_query": query, "proof_hits": int(hits or 0), "proof": proof,
                     "proof_ratio": ratio, "elapsed_s": int(elapsed or 0), "ok": False, "error": fail},
}, ensure_ascii=False))
PY
  fi
  exit 1
fi

if [ "$CV_JSON" = "1" ]; then
  python3 - "$CV_RESP" "$STATUS" "$CHUNKS" "$TOKENS" "$PROOF_QUERY" "$PROOF_HITS" "$PROOF_OK" "$ELAPSED" "$VERIFY" "$SRC_ID" "$DS_ID" "$NAME" "$TYPE" "$TAGS" "$CUSTOM_ID" "$PROOF_RATIO" <<'PY'
import json, sys

(ds, status, chunks, tokens, query, hits, proof, elapsed, verify, sid, dsid,
 name, typ, tags, custom_id, ratio) = sys.argv[1:17]
print(json.dumps({
    "datasource": json.loads(ds),
    "verification": {"status": status, "nbChunks": int(chunks or 0), "nbTokens": int(tokens or 0),
                     "proof_query": query, "proof_hits": int(hits or 0), "proof": proof,
                     "proof_ratio": ratio, "elapsed_s": int(elapsed or 0),
                     "verified": verify == "1", "ok": True},
}, ensure_ascii=False))
PY
else
  python3 - "$STATUS" "$CHUNKS" "$TOKENS" "$PROOF_QUERY" "$PROOF_HITS" "$PROOF_OK" "$ELAPSED" "$VERIFY" "$SRC_ID" "$DS_ID" "$NAME" "$TYPE" "$TAGS" "$CUSTOM_ID" "$UPDATE_ID" "$PROOF_RATIO" <<'PY'
import json, sys

(args) = sys.argv[1:]
(status, chunks, tokens, query, hits, proof, elapsed, verify, sid, dsid,
 name, typ, tags, custom_id, update_id, ratio) = args

if update_id:
    print(f"✅ Fonte atualizada (upsert): {name}")
else:
    print(f"✅ Fonte criada: {name}")
print(f"   id:        {sid}")
print(f"   tipo:      {typ}")
print(f"   base:      {dsid}")
if tags:
    print(f"   tags:      {tags}")
if custom_id:
    print(f"   custom_id: {custom_id}")
print()
if verify == "1":
    print(f"✅ Indexada: status={status}, nbChunks={chunks}, nbTokens={tokens} ({elapsed}s)")
    if proof == "ok":
        print(f"✅ Consulta de prova OK: \"{query[:80]}\" -> {hits} trecho(s) com os termos enviados")
    elif proof == "informativo":
        print(f"ℹ️  Consulta de prova (informativa): {hits} trecho(s)")
    elif proof == "degradado":
        print(f"⚠️  Os trechos retornados não contêm os termos do texto enviado (coincidência: {ratio or '?'}).")
        print("    Veja os avisos acima (upsert que não reindexa / pergunta de prova a refinar).")
else:
    print("⚠️  Indexação NÃO verificada (--no-verify).")
print()
print("Próximos passos:")
print(f"  ./query-base.sh <api-key> {dsid} \"sua pergunta\"")
print(f"  ./list-sources.sh <api-key> {dsid}")
PY
fi
