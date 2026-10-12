# Contrato da API Chatvolt (fonte da verdade)

Última verificação ao vivo: **2026-10-12** (com `CHATVOLT_API_KEY` de teste).
Base URL: `https://api.chatvolt.ai` — Autenticação: `Authorization: Bearer <api-key>`.

Fontes, em ordem de precedência quando divergem:

1. **Probe ao vivo** (`tests/smoke.sh --probe`) — o comportamento real.
2. **`openapi.yaml`** publicado em <https://chat-volt.mintlify.app/openapi.yaml>. A saída crua do último probe fica em `tests/probe/latest.json` (`tests/smoke.sh --probe`), fora do controle de versão.
3. Páginas narrativas da doc: <https://chat-volt.mintlify.app/pages/agents/reference>, `pages/conversations/reference`, `pages/datastores/*`, `pages/errors`.

`llms.txt` completo: <https://chat-volt.mintlify.site/llms-full.txt>.

## 1. Envelope das respostas (verificado)

**Não existe envelope `{data, success, error}`** na maioria das rotas: o objeto/array volta na raiz.

| Rota | Forma real da resposta |
|---|---|
| `GET /agents`, `GET /agents/{id}` | objeto/array na raiz |
| `POST /agents/{id}/query` | `{"answer","sources","messageId","conversationId","visitorId"}` — **na raiz** |
| `GET /agents/{id}/tools` | array na raiz |
| `GET /conversation` | array na raiz |
| `GET /conversation/{id}/messages/{n}` | `{status,isAiEnabled,userId,organizationId,messages:[...]}` |
| `DELETE /conversation/{id}` | `{success,message,conversationId,channel}` |
| `GET /datastores/list`, `GET /datasources/list` | **`{data:[...], pagination:{total,offset,limit,count}}`** |
| `GET/PATCH/DELETE /datastores/{id}` | objeto na raiz |
| `POST /datastores/{id}/query` | **array na raiz** (`[{text,score,datasource_name,datasource_id,custom_id,offset}]`) |
| `GET /datasources/{id}?idstore={ds}` | objeto na raiz |
| `POST /datasources` | objeto na raiz (`status: pending → synched`) |
| `DELETE /datasources/{id}` | objeto deletado na raiz |
| `GET /agents/models` | array na raiz (**público, sem auth**) |

Erros (verificados): `{"error":"NOT_FOUND"}`, `{"error":"UNAUTHORIZED"}`, `{"error":"INVALID_REQUEST"}`, `{"error":"datastoreId is required and must be a single string"}`, `{"error":"Unexpected end of JSON input"}`, `402 {"error":"USAGE_LIMIT"}`.
A doc descreve também `{data:null,success:false,error:{message,code}}` — tratar **as duas formas**.

Detalhes adicionais confirmados em execução real:

- `POST /agents/{id}/query` com `streaming:true` (SSE): eventos `answer` com chunks, um evento `endpoint_response` cujo `data` vem **URL-encoded** (ex.: `data: %7B%22messageId%22...%7D`) e o terminador `data: [DONE]`.
- `GET /conversation/{id}/messages/{n}` e `GET /conversation/{id}` de conversa inexistente/apagada podem responder **HTTP 200 com corpo `null`** — não confie só no status.
- `GET /conversation/{id}/messages/{n}` devolve no máximo `n` mensagens; se vierem exatamente `n`, há mais histórico.

Regra de unwrap usada nos scripts: desembrulhar `d["data"]` somente quando `d` é dict, tem `"data"` e **não** tem `"error"`.

## 2. Divergências da documentação (a doc está errada nestes pontos)

| Afirmação da doc | Realidade verificada |
|---|---|
| `POST /agents/create` (tabela de `pages/agents/reference`) | **404**; o correto é `POST /agents` |
| `POST /agents/{id}/webhook` com body JSON | **não existe**; é `PATCH /agents/{id}/webhook?type=&enabled=` (toggle, sem body) |
| `pages/agents/query`: resposta em `data.content` | resposta em **`answer`** na raiz (o `openapi.yaml` está certo) |
| `pages/datastores/query`: resposta `{data:[...],success}` | **array** na raiz |
| `pages/conversations/reference`: `GET /conversations` (plural) para listar | o endpoint de listagem é **`GET /conversation`** (singular, com filtros) |
| `GET /tools` "form" no CRUD de tools | tipos reais observados na org: `http`, `datastore`, `follow_up_messages`, `delayed_responses`, `artifact_category_selector`, `mark_as_resolved`, `quick_reply_buttons`, `request_human` |
| `api_tool` como tipo de tool | **`400 invalid discriminator`** — a doc lista `api_tool` no array `tools` do agente, mas a API não aceita |
| `POST /agents/{id}/tools` responde `201` | responde **`200`** com o objeto da tool na raiz |
| `GET /agents/{id}/tools/{toolId}` | **404** — só existe `GET` da lista; para ver uma tool, filtrar a lista |
| `GET /datasources/list` sem `datastoreId` | `400 datastoreId is required and must be a single string` |
| `name` é o único campo obrigatório em `POST /agents` | exige também `description` e `systemPrompt` (`400 error invalid request body`) |
| Agentes disponíveis conforme o plano | na organização de teste `POST /agents` com corpo válido → `402 {"error":"USAGE_LIMIT"}`; criar base (`POST /datastores`) continua liberado |

## 3. Parâmetros e limites

- `POST /agents/{id}/query`: `query` (obrigatório), `streaming`, `conversationId`, `visitorId`, `contactId`, `contact{firstName,lastName,email,phoneNumber,userId}`, `temperature`, `modelName`, `presencePenalty`, `frequencyPenalty`, `topP`, `systemPrompt`, `context`, `callbackURL`, `filters{custom_ids,datasource_ids}`.
- `GET /conversation`: `agentId` (aceita a string `null`), `channel`, `createdAt`, `endDate`, `status` (`RESOLVED|UNRESOLVED|HUMAN_REQUESTED`), `priority` (`LOW|MEDIUM|HIGH`), `assigneeId` (`unassigned`), `unread`, `tag`, `ai` (`enabled|disabled`), `adSourceId`, `crmScenarioId`, `crmStepId`, `frustrationMin/Max`, `npsStep`, `npsRating/Min/Max`, `npsCompleted`, `limit` (padrão 25, **máx 100**), `cursor` (JSON URL-safe `{"lastCreatedAt","lastId"}`). **`organizationId` não é parâmetro válido.**
- `GET /datasources/list`: `datastoreId` (obrigatório), `offset` (0), `limit` (20).
- `GET /datasources/{id}`: exige `?idstore={datastoreId}`.
- `PATCH /agents/{id}`: `name,description,modelName,temperature,systemPrompt,visibility,handle,interfaceConfig,enableInactiveHours,inactiveHours,configUrlExternal,configUrlInfosSystemExternal,tools[]`.
  `tools[]` é **estado final**: tool sem `id` é criada, com `id` é atualizada, ausente da lista é **removida**.
- Modelos: `GET /agents/models` (público) → `[{model_name, model_description, hasVision, isToolCallingSupported}]`. **A lista muda** (70 modelos em 2026-10-12); nunca fixar em `SKILL.md`.
- Tools (`/agents/{agentId}/tools`): discriminadores aceitos pelo validador da API — `http`, `lead_capture`, `datastore`, `connector`, `agent`, `form`, `mark_as_resolved`, `request_human`, `delayed_responses`, `follow_up_messages`, `artifact_category_selector`, `channel_transfer`, `quick_reply_buttons`.
  - `POST` → `200` com o objeto na raiz; `PATCH` **exige `type` no corpo** (sem ele: `400 Invalid discriminator value`); `DELETE` → `{success:true, toolId}`.
  - `GET /agents/{id}/tools/{toolId}` → `404`: para ver uma tool, filtrar a listagem.
  - Tool `datastore` ignora `config` (volta `{}`); o vínculo é o campo `datastoreId`.
- Erros/limites (`pages/errors`): 400, 401, 402 (quota do plano), 403, 404, 406 (sessão de canal expirada), 429, 500. Rate limit: **60 req/min**, **10.000 req/dia**, payload **1 MB**, headers `X-RateLimit-*`, `Retry-After`.

## 4. Datastores, fontes e etiquetas (verificado ponta a ponta)

Fluxo válido, executado ao vivo em bases descartáveis (`OMP-*-PROBE`) que foram deletadas:

1. `POST /datastores` `{name,description,type:"qdrant"}` → objeto na raiz, `id` com sufixo `_v3`.
2. `POST /datasources` (JSON) — cria **e atualiza (upsert)**:

```json
{ "id": "<opcional: id existente para upsert>", "name": "doc.md", "datastoreId": "<ds>",
  "type": "file|qa|web_page|web_site", "datasourceText": "conteúdo textual",
  "isUpdateText": true, "config": { "tags": ["a","b"], "custom_id": "tenant-1",
  "mime_type": "text/plain", "fileSize": 95, "question": "", "answer": "", "source_url": "" } }
```

3. Sync é assíncrono: `status: pending → synched`, com `nbChunks/nbTokens/lastSynch` na fonte.
4. `POST /datastores/{id}/query` `{query, topK, filters:{custom_ids,datasource_ids}}` → trechos com `score`, `custom_id`.
5. `DELETE /datasources/{id}` e `DELETE /datastores/{id}` → devolvem o objeto deletado (200).

**Etiquetas (`config.tags`) e `config.custom_id`:**

- Só existem **na fonte** (datasource). O datastore em si não tem tags.
- Definir na criação: funciona (JSON `config.tags`).
- **Alterar depois é um upsert de metadados**: receita verificada — `GET` da fonte atual e `POST /datasources` reenviando `id`, `type`, `datastoreId`, `name`, `isUpdateText:false` e **o `config` completo** com as etiquetas/`custom_id` desejados.
  ⚠️ `config` é **substituído, não mesclado**: campo omitido desaparece. Enviar `config` incompleto (só `{"tags":[...]}`) ou omitir `type`/`name` → `400 INVALID_REQUEST`; `isUpdateText` ausente ou `true` sem `datasourceText` → `400`. `PATCH`/`PUT /datasources/{id}` → `404`.
- **O conteúdo indexado NÃO é substituído pelo upsert**: `datasourceText` é aceito e ignorado; `textSize`/`nbChunks` do chunk permanecem os antigos e a query continua devolvendo o texto original (verificado com texto B e C após o upsert). Para trocar o conteúdo de uma fonte: `DELETE /datasources/{id}` + criar de novo.
- `custom_id` é o filtro multi-tenant efetivo (`filters.custom_ids`): com um id que existe no chunk, retorna o trecho; com id inexistente, retorna `[]`. O chunk só carrega `custom_id` quando ele foi definido na criação da fonte.

**Upload multipart (`POST /datasources` com `-F file=@...`) — NÃO indexa:**

- Verificado: o arquivo vai para o bucket como `.bin`/`application/octet-stream`, `nbChunks = 0`, e `config` em campo de formulário é **ignorado** (só `fileName` e `custom_id` como campos soltos são aceitos).
- Portanto o caminho confiável é **JSON + `datasourceText`**: ler o arquivo local (`.md`, `.txt`, `.csv`, `.html`, `pdftotext -layout` para PDF) e enviar o texto. O multipart não é usado por nenhuma skill.

**Outros detalhes verificados nas bases:**

- `pluginDescriptionForHumans` recebe o prefixo `About ` automaticamente (não repetir no valor enviado).
- Id inexistente (inclusive recém-deletado) responde `401 UNAUTHORIZED` em `GET /datastores/{id}` e em `GET /datasources/list?datastoreId=`, **não** 404.
- A resposta de `POST /datastores/{id}/query` omite os campos nulos (`datasource_name`, `custom_id`, `tags`).

## 5. Convenções dos scripts

- Todo script: `API_KEY` via argv ou `CHATVOLT_API_KEY`; `AGENT_ID` via argv ou `CHATVOLT_AGENT_ID`.
- `CV_API_BASE` sobrescreve a base URL (usado pelo stub offline de teste); padrão `https://api.chatvolt.ai`.
- `CV_JSON=1` → imprime **somente JSON** em stdout e todos os diagnósticos em stderr (contrato usado pelos testes headless).
- Helpers em `scripts/_lib.sh`, **idêntico em todas as skills** (a suíte verifica por sha256): `cv_err_msg`, `cv_unwrap`, `cv_request`, `cv_emit`, `cv_die`.
- Nunca interpolar valores em código Python por string; construir payloads com `python3 - "$arg"` + `sys.argv`.
- Toda operação destrutiva (delete, PATCH de prompt, upsert que reescreve texto) exige confirmação (`CV_YES=1` para pular em teste).

## 6. Cobertura: o que a API expõe e o que está acessível

`openapi.yaml` publicado: **136 operações em 87 paths / 23 grupos**. Índice completo em
`api-call/data/endpoints.json` (`api-call/scripts/catalog.sh`), com a disponibilidade medida ao vivo.

Disponibilidade verificada (2026-10-12, plano/organização de teste):

| Rota | Estado |
|---|---|
| `/agents*`, `/agents/{id}/tools*`, `/agents/models` | disponível |
| `/agent-whitelist-whatsapp/{id}` | disponível |
| `GET /contacts` | disponível: `{contacts:[…], count, hasMore, nextCursor}` — paginação por **cursor** (`<dataISO>_<id>`), filtros `--search`, `--has-email` etc. |
| `/contacts/variables`, `DELETE /contacts/{id}` | disponível (variáveis exigem `contactId`) |
| `GET /contacts/available-variables` | existe ao vivo (**fora do openapi publicado**) → `{variables:{…}}` |
| `GET /contacts/{id}` | **não existe** (só `DELETE` nesse path) |
| `/conversation*` (lista, detalhe, mensagens), `/variables/{conversationId}`, `/conversations/{id}/notes` | disponível — `POST /notes` → **201**, `PUT` → 200, `DELETE` → **204 com corpo vazio**; a listagem **não** devolve notas privadas |
| `DELETE /variables/{conversationId}/{varName}` | 200 com `{message, deleted:{…}}` |
| `/conversations/{id}/set-status` (e afins) | 200 com `{success:true, message:"Conversation Status changed."}` |
| `/conversations/{id}/tags` | **401** — exige sessão do dashboard, não API key |
| `/conversations/{id}/export` | disponível, **binário**: `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` (xlsx, ~8 KB por conversa) |
| `/conversations/export` (lote) | **404** |
| `/conversations/history` | disponível (exige `email` + `agentId`) → `{conversations:[], nextCursor}` |
| `/crm/scenario`, `/crm/step`, `/crm/conversationLog`, `/crm/conversation/count` | disponível |
| `/crm/events` | **streaming SSE** (`text/event-stream`, evento inicial `CONNECTED`) |
| `/datastores*`, `/datasources*` | disponível |
| `/dispatches`, `/dispatches/contacts/lists` | disponível: `{dispatches:[…], count}` e `{lists:[…], count}` (sem `total`) — **`GET /dispatches/{id}` não existe** (404) e `DELETE /dispatches?id=inexistente` responde **500**, não 404 |
| `/dispatches/contacts` | disponível (exige `contactListId`; `GET /dispatches/contacts/{id}` inexistente → `404 {"error":"Contact not found"}`) |
| `/artifacts`, `/artifacts/search`, `/artifact-categories` | disponível |
| `/artifacts/media` | disponível (exige `artifact_id`) |
| `/whatsapp/templates` | disponível: `GET` exige `agentId` e devolve envelope `{data:[…]}`; agente sem WABA → `400 Agent does not have WhatsApp configured` |
| `/mercadolivre/products` | disponível: exige `agentId` **e** `serviceProviderId`; `{products, total, page, perPage}` (aceita `page`/`perPage`) |
| `/mercadolivre/products/count` | disponível: `{count}` da organização; com `agentId` conta só o agente; `serviceProviderId` é ignorado |
| `/mercadolivre/get-products` | disponível: sem `agentId` → `400 Agent ID is required`; agente sem integração → `404 Mercado Livre service provider not found for this agent` |
| `/tags`, `/tags/delete-by-name`, `/tags/get-visible-tags` | **404** neste ambiente |
| `/agent-blacklist`, `/agent-templates/{organizationId}` | **404** neste ambiente |
| `/webhook/validate` | **404**; `/webhook/webhook` é endpoint de recebimento (não de cliente) |
| `/whatsapp/conversion-tracking` | **404** |
| `/messages/interactive/*`, `/whatsapp/{phoneNumberId}/template-message`, `/twilio/*`, `/zapi/*`, `/zapper/*` | rotas de **envio real** — nunca disparar em contatos reais; verificar só no stub |
| `/forms/{formId}/chat` | disponível (envia formulário ao agente) |

## 7. Cobertura final

Todas as 136 operações publicadas têm skill dedicada ou ficam acessíveis por `api-call/scripts/call.sh`
(que não depende de contrato específico). O único endpoint que **não** é utilizável como cliente é
`POST /webhook/webhook` (recebimento de payload externo pela plataforma).
