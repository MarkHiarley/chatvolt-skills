---
name: chatvolt-datastore-add
description: >
  Adiciona conteúdo a uma base de conhecimento (datastore) da Chatvolt: cria a base,
  envia fontes de texto/arquivo/PDF/pergunta-resposta/URL, confere a indexação
  (status synched + nbChunks > 0 + consulta de prova), consulta a base e conecta o
  datastore como tool de um agente.
---

# Adicionar conteúdo à base de conhecimento (datastore)

Você me dá a base (ou o nome de uma nova) e o conteúdo — texto, arquivo, PDF, par
pergunta/resposta ou URL — e eu envio a fonte pela API, **espero a indexação terminar**
(`status: synched` com `nbChunks > 0`), **rodo uma consulta de prova** para confirmar
que o conteúdo ficou recuperável e, se você quiser, conecto a base ao agente como tool
do tipo `datastore`.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys) e o
> `<datastore-id>` (o id termina em `_v3`) e/ou o `<agent-id>`.
> Exporte `CHATVOLT_API_KEY` ou passe a chave como 1º argumento.

## Como funciona

1. **Base** — `create-datastore.sh` cria a base vazia (`POST /datastores`) e devolve o
   `id`; `list-datastores.sh`/`get-datastore.sh` mostram o que já existe.
2. **Conteúdo** — `add-source.sh` decide o caminho do conteúdo:
   - `--text`/`--text-file`/`--file` (texto, `.md`, `.txt`, `.csv`, `.json`, `.html`, …) →
     lê o conteúdo local e envia como `datasourceText` (`type: "file"`);
   - `--file` com PDF → extrai o texto com `pdftotext` e envia como texto;
   - `--qa "pergunta::resposta"` → `type: "qa"`, com `config.question`/`config.answer` e o
     texto `"Pergunta: …\nResposta: …"` como conteúdo indexado;
   - `--url <url>` (e `--site`) → `type: "web_page"`/`"web_site"`, indexado pelo servidor
     a partir de `config.source_url`.
   O envio é **um único `POST /datasources` em JSON** — nunca multipart.
3. **Verificação (obrigatória)** — depois de criar, o script aproveita o estado da
   resposta do `POST` e, se ainda não estiver pronto, faz polling em
   `GET /datasources/{id}?idstore={datastoreId}` até `status == "synched"`
   (`--timeout`, padrão 90s, 429 respeitado pelo retry), exigindo `nbChunks > 0` e uma
   consulta de prova em `POST /datastores/{id}/query` com `filters.datasource_ids` que
   retorne ao menos um trecho. Falhou → sai com código 1 e mostra o comando para remover
   a fonte. Como controle extra, a pergunta de prova (derivada do próprio conteúdo) é
   comparada com o texto dos trechos: se menos de 50% dos termos significativos
   aparecerem, o script avisa (é o sintoma do upsert que não reindexa).
4. **Uso** — `query-base.sh` responde "o que a base sabe sobre X" com score/offset/texto;
   `attach-to-agent.sh` publica a base para o agente consultar.

## API usada

| Método | Endpoint | Descrição |
|---|---|---|
| GET | `/datastores/list?offset=&limit=` | lista bases → `{data:[...], pagination:{...}}` |
| POST | `/datastores` | cria base (`type: "qdrant"`) → objeto na raiz |
| GET | `/datastores/{id}?limit=&search=&status=&type=` | base + `datasources[]` filtradas |
| PATCH | `/datastores/{id}` | atualiza nome/descrição/plugin/visibilidade |
| DELETE | `/datastores/{id}` | apaga a base e as fontes dela |
| POST | `/datastores/{id}/query` | busca trechos → **array na raiz** |
| GET | `/datasources/list?datastoreId=&offset=&limit=` | fontes da base (`datastoreId` obrigatório) |
| POST | `/datasources` | cria fonte **e** faz upsert quando vem `id` |
| GET | `/datasources/{id}?idstore={datastoreId}` | estado da fonte (status, nbChunks, tokens) |
| DELETE | `/datasources/{id}` | apaga a fonte → objeto deletado na raiz |
| GET | `/agents/{agentId}/tools` | tools do agente |
| POST | `/agents/{agentId}/tools` | cria a tool `{"type":"datastore","datastoreId"}` |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` ·
docs: <https://chat-volt.mintlify.app/pages/datastores/reference>

### Campos da fonte (`POST /datasources`)

| Campo | Onde | Observação |
|---|---|---|
| `type` | topo | `file`, `qa`, `web_page`, `web_site` |
| `datastoreId` | topo | obrigatório |
| `name` | topo | nome da fonte (o script deriva do arquivo/texto/pergunta) |
| `datasourceText` | topo | **conteúdo indexado** (para `file` e `qa`) |
| `isUpdateText` | topo (verify) | enviado junto com `datasourceText`; o `openapi.yaml` o coloca dentro de `config` |
| `id` | topo | upsert: id de uma fonte existente |
| `config.tags` | config | etiquetas da fonte — **defina na criação** |
| `config.custom_id` | config | id de filtro (`filters.custom_ids`) |
| `config.mime_type` / `config.fileSize` | config | metadados do conteúdo enviado |
| `config.question` / `config.answer` | config | usados no tipo `qa` |
| `config.source_url` | config | URL de origem no tipo `web_page`/`web_site` |

Resposta: objeto na raiz, `status: "pending" → "synched"`, com `nbChunks`, `nbTokens`,
`textSize`, `nbSynch`, `lastSynch`.

### Limites e comportamentos verificados ao vivo (2026-10-12)

| Fato | Detalhe |
|---|---|
| Payload | **1 MB** por requisição (o script recusa texto > 950.000 bytes) |
| Rate limit | **60 req/min** e **10.000 req/dia**; headers `X-RateLimit-*`, `Retry-After`; 429 é retentado |
| `POST /datasources` | é **upsert**: com `id` no corpo, atualiza a fonte existente |
| Upsert de conteúdo | **não reindexa**: o registro da fonte muda (nome, tamanho, `nbSynch`) mas os chunks continuam com o texto anterior (testado com `isUpdateText` no topo e dentro de `config`). Para trocar conteúdo: `delete-source.sh` + reenvio |
| Multipart | `POST /datasources` com `-F file=@...` grava o arquivo como binário (`.bin`), ignora `config` e resulta em **`nbChunks: 0`** — por isso ele não é usado aqui |
| Binários | `.docx/.xlsx/...` não têm extrator embutido: o script recusa com instruções (`libreoffice`, `pandoc`) em vez de enviar algo que não indexa. PDF usa `pdftotext` (PDF digitalizado ⇒ erro pedindo OCR) |
| `pluginDescriptionForHumans` | a API prefixa `About ` automaticamente — envie só o texto da descrição |
| `config.custom_id` | fica gravado na fonte, mas nos testes desta organização a busca com `filters.custom_ids` devolveu `[]` mesmo com o `custom_id` correto na fonte; para segmentação multi-tenant, valide com a skill `chatvolt-datastore-tags` (`query-verify.sh`) |
| Resposta da query | pode vir sem `datasource_name`/`custom_id`/`tags` (campos nulos são omitidos pelo servidor) |
| Id inexistente | `GET /datastores/{id}` e `GET /datasources/list?datastoreId=` com um id inexistente (inclusive recém-deletado) respondem **401 UNAUTHORIZED**, não 404 — se a chave está certa, provavelmente o id foi apagado |
| Etiquetas | só existem **na fonte** (`config.tags`); alterar depois exige upsert com `datasourceText` (o `PATCH`/`PUT` da fonte responde 404) — use a skill `chatvolt-datastore-tags` |

## Scripts auxiliares

- `list-datastores.sh <key> [--limit N] [--offset N] [--all]` — lista as bases com tipo,
  visibilidade, nº de fontes e data de criação.
- `get-datastore.sh <key> <datastore-id> [--limit N] [--search S] [--status S] [--type T]` —
  metadados da base + tabela de fontes (status, chunks, tokens, tags, custom_id).
- `create-datastore.sh <key> --name <n> [--description D] [--plugin-name N] [--plugin-description D] [--public]` —
  cria a base; valida os limites de 20/90 caracteres do plugin.
- `update-datastore.sh <key> <datastore-id> [--name N] [--description D] [--plugin-name N] [--plugin-description D] [--public|--private]` —
  mostra o diff, confirma (`CV_YES=1`) e aplica o `PATCH`.
- `delete-datastore.sh <key> <datastore-id>` — mostra nome e nº de fontes, confirma e apaga
  a base inteira (avisa que tools de agentes ficam com `datastoreId` inexistente).
- `list-sources.sh <key> <datastore-id> [--limit N] [--offset N] [--all] [--status S] [--tag T]` —
  fontes da base; lembra que `synched` com `CHUNKS=0` significa nada indexado.
- `get-source.sh <key> <datastore-id> <source-id>` — ficha da fonte: indexação + metadados,
  com veredito (indexada / ainda indexando / synched com nbChunks=0).
- `add-source.sh <key> <datastore-id> (--text | --text-file | --file | --qa | --url [--site]) [--name N] [--tags a,b] [--custom-id X] [--update <source-id>] [--query Q] [--timeout S] [--no-verify]` —
  envia a fonte e **verifica a indexação**; falha com código 1 explicando o motivo.
- `delete-source.sh <key> <datastore-id> <source-id>` — mostra a fonte, confirma e apaga.
- `query-base.sh <key> <datastore-id> <query> [--top-k N] [--custom-id X[,Y]] [--datasource-id Y[,Z]]` —
  tabela de trechos com score/offset/fonte/custom_id e o texto.
- `attach-to-agent.sh <key> <agent-id> <datastore-id> [--name N] [--description D]` — cria a
  tool `datastore` no agente, confere na listagem e não cria duplicata se a base já estiver
  conectada.
- `manage-base.sh <key> [<datastore-id>]` — menu interativo que delega para os scripts acima.

### Variáveis de ambiente

- `CV_JSON=1` — stdout somente JSON, diagnósticos em stderr (contrato dos testes headless).
- `CV_YES=1` — pula as confirmações (delete/upsert).
- `CV_API_BASE` — sobrescreve a base URL (stub offline).
- `CV_POLL_INTERVAL` — intervalo do polling de indexação em segundos (padrão 3).

### Códigos de saída

`0` ok · `1` erro de cliente (inclui verificação de indexação falhada) · `3` quota (402) ·
`4` rede · `5` servidor · `130` cancelado pelo usuário.

### Fluxo completo (exemplo)

```bash
KEY="$CHATVOLT_API_KEY"
AGENT_ID="seu-agent-id"

# 1. base nova (CV_JSON=1 devolve só o JSON; o id está em .id)
DS=$(CV_JSON=1 ./create-datastore.sh "$KEY" --name "Base Produto X" \
      --plugin-name "Produto X" --plugin-description "Documentação do produto X" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

# 2. conteúdo (com verificação de indexação embutida)
./add-source.sh "$KEY" "$DS" --text-file manual.md --tags "manual,2027" --custom-id tenant-1
./add-source.sh "$KEY" "$DS" --file politica.pdf
./add-source.sh "$KEY" "$DS" --qa "Qual o prazo de garantia?::36 meses a partir da nota."

# 3. conferir e consultar
./list-sources.sh "$KEY" "$DS" --all
./query-base.sh "$KEY" "$DS" "Qual o prazo de garantia?" --top-k 5

# 4. publicar para o agente
./attach-to-agent.sh "$KEY" "$AGENT_ID" "$DS"

# 5. remover (fonte específica ou a base inteira)
./delete-source.sh "$KEY" "$DS" <source-id>
./delete-datastore.sh "$KEY" "$DS"
```
