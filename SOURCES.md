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

## 8. Código-fonte e checagem de atualizações (2026-10-30)

O código da API pública está no monorepo `appchatvolt_dev` (`apps/dashboard/pages/api`).
O `next.config.js` mapeia o host `api.chatvolt.ai` para essas rotas (`/agents/:path*` →
`/api/agents/:path*`, e assim por diante). Por isso, uma rota existir em `pages/api` **não**
garante que ela é pública: a API pública é só o que está nas regras de rewrite com
`has: host api.chatvolt.ai`.

Autenticação: `packages/lib/auth.ts` marca a sessão com `authType` = `apiKey` (chave `Bearer`)
ou `session` (login no dashboard). Rotas que checam `authType === 'session'` não aceitam chave.

**Verificado só no código-fonte (não ao vivo):**

- `POST /agents/generate-prompt`, `POST /agents/check-handle-available` e
  `GET /agent-templates/{organizationId}` aceitam API key. Contratos na seção de
  `agent-admin/SKILL.md`.
- `POST /agents/{id}/clone` exige sessão de SUPERADMIN; com API key responde 403.
- `GET /agent-templates/{organizationId}` só aceita a organização de templates configurada
  (`NEXT_PUBLIC_ORGANIZATION_ID_TEMPLATES`); outro id responde 404.

**Operações publicadas em `apps/docs` sem cobertura:** agora estão documentadas na seção 9 (com a situação real de cada uma). Com o catálogo atualizado, a checagem não lista mais essas operações como pendentes.

**Checagem de atualizações (`scripts/check-updates.sh`, função `cv_check_updates` em `_lib.sh`):**

- Compara o OpenAPI publicado (`https://chat-volt.mintlify.app/openapi.yaml`, mesmo conteúdo do
  `chatvolt-docs/openapi.yaml`) com o catálogo `api-call/data/endpoints.json`, e guarda o sha
  para detectar mudanças entre execuções.
- Lista as operações de `apps/docs` fora do catálogo.
- Compara o HEAD do clone local `appchatvolt_dev` (`CV_SRC`) com o último visto e lista os
  arquivos de API/doc alterados. O clone não é atualizado sozinho: use `git pull` nele.
- Estado em `${CV_STATE_DIR:-~/.local/state/chatvolt-skills}/updates.json`. `CV_UPDATE_CHECK=0`
  desliga; sem rede, a checagem vira um aviso e a skill segue.

## 9. Operações documentadas em `apps/docs` (situação verificada no código, 2026-10-30)

Fonte: `apps/docs/api-reference/endpoint/**/*.mdx` (a fonte do docs.chatvolt.ai). Estas 16
operações foram adicionadas a `api-call/data/endpoints.json` com a situação abaixo. **Nenhuma foi
testada ao vivo** (sem chave de teste nesta sessão). A coluna "Código" vem de
`apps/dashboard/pages/api` e das rewrites de `next.config.js`.

| Operação | Código | Situação |
|---|---|---|
| `POST /crm/card` | existe; **400 ao vivo** sem corpo (`agentId is required`), ou seja, rota existe | A página da doc está vazia: corpo e resposta não documentados |
| `GET /api/logs/{conversationId}/assignment-history` | existe (`logs/[id]/assignment-history.ts`); **200 ao vivo** em `api.chatvolt.ai/api/logs/{id}/...` (sem `/api`: 404) | Resposta documentada: `periods`, `legacy`, `hasMore` |
| `POST /whatsapp/conversion-tracking` | existe; **400 ao vivo** sem corpo (exige conversa identificável), ou seja, rota existe | Doc completa (Meta CAPI para CTWA) |
| `POST /datastores/file-upload/generate-link/{datastoreId}` | existe, via rewrite para `external/datastores/file-upload/generate-link` | Corpo: `type`, `fileName`. Resposta: `id`, `link` |
| `POST /datastores/file-upload/{datastoreId}` | existe, via rewrite para `external/datastores/file-upload` | Corpo: `id` (do link gerado) |
| `POST /datastores/update/{datastoreId}` | existe, via rewrite para `external/datastores/update` | **Deprecated** na doc |
| `POST /datastores/upsert/{datastoreId}` | existe, via rewrite para `external/datastores/upsert` | **Deprecated** na doc |
| `POST /datastores/query/{datastore_id}/old` | **não encontrado**; **404 ao vivo** (página do Next.js) | A doc a apresenta como existente; sem rota correspondente |
| `GET /conversation-event-log` | sem rota; **404 ao vivo** | **Indisponível**: a doc diz que a implementação está desativada temporariamente |
| `DELETE /dispatches/contacts/link` | sem rota | Não implementado (a doc diz "not yet implemented"). `GET` ao vivo responde 404 `not found` (texto puro) |
| `GET /dispatches/contacts/link` | sem rota | Não implementado |
| `GET /dispatches/{id}` | sem rota | Não implementado; a doc manda usar `GET /dispatches` |
| `GET /crm/scenario/{scenarioId}` | sem rota | Não implementado; a doc manda usar `GET /crm/scenario` |
| `GET /crm/step/{stepId}` | sem rota | Não implementado; a doc manda usar `GET /crm/step` |
| `GET /crm/step/{stepId}/conversation` | sem rota | Não implementado |
| `POST /crm/scenario/{scenarioId}/conversation` | sem rota | Não implementado |

**Implicação para as skills:** operações "não implementadas" ou "indisponíveis" não devem virar
scripts. O `check-updates.sh` deixa de listar as 16 como pendentes porque estão no catálogo.


## 10. Rotas no código sem documentação (2026-10-30)

Rotas encontradas em `apps/dashboard/pages/api` que não estão no catálogo nem em `apps/docs`.
Foram listadas para que nada fique fora do repositório. **Não foram testadas**, e algumas podem
exigir sessão do dashboard (checagem `authType === 'session'` no handler, ou escrita restrita).
Não confirmei quais delas o host `api.chatvolt.ai` expõe pelas rewrites, porque o mapeamento
completo não está todo lido. **A rota `POST /agents/{id}/clone` foi deixada de fora**, a pedido:
ela só aceita sessão de SUPERADMIN.

Método extraído de `handler.get/post/put/patch/delete(...)` e das strings de método no arquivo.
Se o arquivo tiver mais de um método, cada um aparece em sua linha.

**`/agent-whitelist-whatsapp`**
- `GET /agent-whitelist-whatsapp` — `apps/dashboard/pages/api/agent-whitelist-whatsapp/index.ts`
- `PUT /agent-whitelist-whatsapp/{}` — `apps/dashboard/pages/api/agent-whitelist-whatsapp/[agentId]/index.ts`

**`/agents`**
- `DELETE /agents/{}/artifact-categories` — `apps/dashboard/pages/api/agents/[id]/artifact-categories.ts`
- `DELETE /agents/{}/crm-config` — `apps/dashboard/pages/api/agents/[id]/crm-config/index.ts`
- `GET /agents` — `apps/dashboard/pages/api/agents/index.ts`
- `GET /agents/{}/artifact-categories` — `apps/dashboard/pages/api/agents/[id]/artifact-categories.ts`
- `GET /agents/{}/crm-config` — `apps/dashboard/pages/api/agents/[id]/crm-config/index.ts`
- `GET /agents/{}/public` — `apps/dashboard/pages/api/agents/[id]/public.ts`
- `GET /agents/{}/quick-messages` — `apps/dashboard/pages/api/agents/[id]/quick-messages.ts`
- `GET /agents/{}/tags` — `apps/dashboard/pages/api/agents/[id]/tags.tsx`
- `GET /agents/{}/tool-config` — `apps/dashboard/pages/api/agents/[id]/tool-config.ts`
- `POST /agents/generate-qa` — `apps/dashboard/pages/api/agents/generate-qa.ts`
- `POST /agents/query` — `apps/dashboard/pages/api/agents/query.ts`
- `POST /agents/{}/artifact-categories` — `apps/dashboard/pages/api/agents/[id]/artifact-categories.ts`
- `POST /agents/{}/capture` — `apps/dashboard/pages/api/agents/[id]/capture.tsx`
- `POST /agents/{}/crm-config` — `apps/dashboard/pages/api/agents/[id]/crm-config/index.ts`
- `POST /agents/{}/generate-upload-link` — `apps/dashboard/pages/api/agents/[id]/generate-upload-link.ts`
- `POST /agents/{}/simplequery` — `apps/dashboard/pages/api/agents/[id]/simplequery.tsx`
- `PUT /agents/{}/artifact-categories` — `apps/dashboard/pages/api/agents/[id]/artifact-categories.ts`
- `PUT /agents/{}/quick-messages` — `apps/dashboard/pages/api/agents/[id]/quick-messages.ts`

**`/artifact-categories`**
- `POST /artifact-categories/import` — `apps/dashboard/pages/api/artifact-categories/import.ts`

**`/artifacts`**
- `GET /artifacts/media-by-name` — `apps/dashboard/pages/api/artifacts/media-by-name.ts`
- `POST /artifacts/import-whatsapp` — `apps/dashboard/pages/api/artifacts/import-whatsapp.ts`
- `POST /artifacts/searches/log` — `apps/dashboard/pages/api/artifacts/searches/log.ts`

**`/contacts`**
- `DELETE /contacts/batch-delete` — `apps/dashboard/pages/api/contacts/batch-delete.ts`
- `DELETE /contacts/bulk-delete-by-filter` — `apps/dashboard/pages/api/contacts/bulk-delete-by-filter.ts`
- `GET /contacts/ctwa-ads` — `apps/dashboard/pages/api/contacts/ctwa-ads.ts`
- `POST /contacts/batch-create` — `apps/dashboard/pages/api/contacts/batch-create.ts`
- `POST /contacts/export` — `apps/dashboard/pages/api/contacts/export.ts`
- `POST /contacts/import-csv` — `apps/dashboard/pages/api/contacts/import-csv.ts`
- `POST /contacts/merge` — `apps/dashboard/pages/api/contacts/merge.ts`
- `PUT /contacts/{}` — `apps/dashboard/pages/api/contacts/[id]/index.ts`

**`/conversation`**
- `GET /conversation/{}/contact` — `apps/dashboard/pages/api/conversation/[conversationId]/contact.ts`
- `POST /conversation/dislike` — `apps/dashboard/pages/api/conversation/dislike.ts`
- `POST /conversation/{}/contact` — `apps/dashboard/pages/api/conversation/[conversationId]/contact.ts`

**`/conversations`**
- `DELETE /conversations/{}` — `apps/dashboard/pages/api/conversations/[conversationId]/index.tsx`
- `DELETE /conversations/{}/tags` — `apps/dashboard/pages/api/conversations/[conversationId]/tags.ts`
- `GET /conversations` — `apps/dashboard/pages/api/conversations/index.ts`
- `GET /conversations/reminders` — `apps/dashboard/pages/api/conversations/reminders.ts`
- `GET /conversations/validate` — `apps/dashboard/pages/api/conversations/validate.ts`
- `GET /conversations/{}` — `apps/dashboard/pages/api/conversations/[conversationId]/index.tsx`
- `GET /conversations/{}/quick-messages` — `apps/dashboard/pages/api/conversations/[conversationId]/quick-messages.ts`
- `PATCH /conversations/activate-ai` — `apps/dashboard/pages/api/conversations/activate-ai.ts`
- `PATCH /conversations/{}` — `apps/dashboard/pages/api/conversations/[conversationId]/index.tsx`
- `PATCH /conversations/{}/nps-override` — `apps/dashboard/pages/api/conversations/[conversationId]/nps-override.ts`
- `POST /conversations/eval-answer` — `apps/dashboard/pages/api/conversations/eval-answer.ts`
- `POST /conversations/export` — `apps/dashboard/pages/api/conversations/export.ts`
- `POST /conversations/redistribute` — `apps/dashboard/pages/api/conversations/redistribute.ts`
- `POST /conversations/update-status` — `apps/dashboard/pages/api/conversations/update-status.ts`
- `POST /conversations/{}` — `apps/dashboard/pages/api/conversations/[conversationId]/index.tsx`
- `POST /conversations/{}/claim` — `apps/dashboard/pages/api/conversations/[conversationId]/claim.ts`
- `POST /conversations/{}/mark-read` — `apps/dashboard/pages/api/conversations/[conversationId]/mark-read.ts`
- `POST /conversations/{}/mark-unread` — `apps/dashboard/pages/api/conversations/[conversationId]/mark-unread.ts`
- `POST /conversations/{}/message` — `apps/dashboard/pages/api/conversations/[conversationId]/message.tsx`
- `POST /conversations/{}/nps` — `apps/dashboard/pages/api/conversations/[conversationId]/nps.tsx`
- `POST /conversations/{}/quick-messages` — `apps/dashboard/pages/api/conversations/[conversationId]/quick-messages.ts`
- `POST /conversations/{}/schedule-followup` — `apps/dashboard/pages/api/conversations/[conversationId]/schedule-followup.ts`
- `POST /conversations/{}/transfer-channel` — `apps/dashboard/pages/api/conversations/[conversationId]/transfer-channel.ts`
- `POST /conversations/{}/typing` — `apps/dashboard/pages/api/conversations/[conversationId]/typing.ts`
- `PUT /conversations/reminders` — `apps/dashboard/pages/api/conversations/reminders.ts`
- `PUT /conversations/{}/quick-messages` — `apps/dashboard/pages/api/conversations/[conversationId]/quick-messages.ts`

**`/crm`**
- `GET /crm/step/{}/removed-count` — `apps/dashboard/pages/api/crm/step/[id]/removed-count.ts`
- `PUT /crm/scenario/order` — `apps/dashboard/pages/api/crm/scenario/order/index.ts`
- `PUT /crm/step/conversation/order` — `apps/dashboard/pages/api/crm/step/conversation/order/index.ts`
- `PUT /crm/step/order` — `apps/dashboard/pages/api/crm/step/order/index.ts`

**`/datasources`**
- `GET /datasources/running` — `apps/dashboard/pages/api/datasources/running.ts`
- `GET /datasources/{}/chunks/{}` — `apps/dashboard/pages/api/datasources/[id]/chunks/[chunkId].ts`
- `POST /datasources/bulk-delete` — `apps/dashboard/pages/api/datasources/bulk-delete.ts`
- `POST /datasources/check` — `apps/dashboard/pages/api/datasources/check.ts`
- `POST /datasources/{}/synch` — `apps/dashboard/pages/api/datasources/[id]/synch.ts`

**`/datastores`**
- `DELETE /datastores/{}/api-keys` — `apps/dashboard/pages/api/datastores/[id]/api-keys.ts`
- `GET /datastores` — `apps/dashboard/pages/api/datastores/index.ts`
- `GET /datastores/{}/api-keys` — `apps/dashboard/pages/api/datastores/[id]/api-keys.ts`
- `POST /datastores/{}/api-keys` — `apps/dashboard/pages/api/datastores/[id]/api-keys.ts`
- `POST /datastores/{}/generate-upload-link` — `apps/dashboard/pages/api/datastores/[id]/generate-upload-link.ts`

**`/dispatches`**
- `GET /dispatches/{}/logs` — `apps/dashboard/pages/api/dispatches/[id]/logs.ts`
- `POST /dispatches/contacts/lists/from-filter` — `apps/dashboard/pages/api/dispatches/contacts/lists/from-filter.ts`
- `POST /dispatches/total-contacts` — `apps/dashboard/pages/api/dispatches/total-contacts.ts`
- `POST /dispatches/{}/retry` — `apps/dashboard/pages/api/dispatches/[id]/retry.ts`
- `POST /dispatches/{}/stop` — `apps/dashboard/pages/api/dispatches/[id]/stop.ts`
- `PUT /dispatches/{}/archive` — `apps/dashboard/pages/api/dispatches/[id]/archive.ts`

**`/external`**
- `POST /external/datastores/file-upload/generate-link/{}` — `apps/dashboard/pages/api/external/datastores/file-upload/generate-link/[id].ts`
- `POST /external/datastores/file-upload/process/{}` — `apps/dashboard/pages/api/external/datastores/file-upload/process/[id].ts`
- `POST /external/datastores/file-upload/{}` — `apps/dashboard/pages/api/external/datastores/file-upload/[id].ts`
- `POST /external/datastores/update/{}` — `apps/dashboard/pages/api/external/datastores/update/[id].ts`
- `POST /external/datastores/upsert/{}` — `apps/dashboard/pages/api/external/datastores/upsert/[id].ts`

**`/forms`**
- `DELETE /forms/{}` — `apps/dashboard/pages/api/forms/[formId]/index.tsx`
- `DELETE /forms/{}/admin` — `apps/dashboard/pages/api/forms/[formId]/admin.ts`
- `GET /forms` — `apps/dashboard/pages/api/forms/index.ts`
- `GET /forms/{}` — `apps/dashboard/pages/api/forms/[formId]/index.tsx`
- `GET /forms/{}/submissions` — `apps/dashboard/pages/api/forms/[formId]/submissions.ts`
- `PATCH /forms/{}/admin` — `apps/dashboard/pages/api/forms/[formId]/admin.ts`
- `POST /forms` — `apps/dashboard/pages/api/forms/index.ts`
- `POST /forms/{}` — `apps/dashboard/pages/api/forms/[formId]/index.tsx`
- `POST /forms/{}/publish` — `apps/dashboard/pages/api/forms/[formId]/publish.ts`

**`/logs`**
- `GET /logs` — `apps/dashboard/pages/api/logs/index.ts`
- `GET /logs/count-unread` — `apps/dashboard/pages/api/logs/count-unread.ts`
- `GET /logs/{}` — `apps/dashboard/pages/api/logs/[id]/index.tsx`
- `PATCH /logs/{}` — `apps/dashboard/pages/api/logs/[id]/index.tsx`

**`/mercadolivre`**
- `GET /mercadolivre/products/sync` — `apps/dashboard/pages/api/mercadolivre/products/sync.ts`
- `POST /mercadolivre/products` — `apps/dashboard/pages/api/mercadolivre/products/index.ts`
- `POST /mercadolivre/products/bulk-update` — `apps/dashboard/pages/api/mercadolivre/products/bulk-update.ts`

**`/messages`**
- `DELETE /messages/{}` — `apps/dashboard/pages/api/messages/[messageId].ts`
- `POST /messages/mark-all-read` — `apps/dashboard/pages/api/messages/mark-all-read.ts`
- `PUT /messages/{}` — `apps/dashboard/pages/api/messages/[messageId].ts`

**`/tags`**
- `DELETE /tags/delete-by-name` — `apps/dashboard/pages/api/tags/delete-by-name.ts`

**`/variables`**
- `PATCH /variables/{}` — `apps/dashboard/pages/api/variables/[conversationId]/index.ts`
- `PATCH /variables/{}/{}` — `apps/dashboard/pages/api/variables/[conversationId]/[varName]/index.ts`
- `POST /variables/{}` — `apps/dashboard/pages/api/variables/[conversationId]/index.ts`
- `POST /variables/{}/{}` — `apps/dashboard/pages/api/variables/[conversationId]/[varName]/index.ts`

**`/voltapi`**
- `POST /voltapi` — `apps/dashboard/pages/api/voltapi/index.ts`

**`/webhook`**
- `GET /webhook/get-data-users` — `apps/dashboard/pages/api/webhook/get-data-users.ts`
- `POST /webhook/validate` — `apps/dashboard/pages/api/webhook/validate.ts`

**`/whatsapp`**
- `DELETE /whatsapp/templates/{}` — `apps/dashboard/pages/api/whatsapp/templates/[templateId].ts`
- `GET /whatsapp/templates/{}` — `apps/dashboard/pages/api/whatsapp/templates/[templateId].ts`
- `POST /whatsapp/templates/send-test` — `apps/dashboard/pages/api/whatsapp/templates/send-test.ts`
- `POST /whatsapp/templates/upload-media` — `apps/dashboard/pages/api/whatsapp/templates/upload-media.ts`
- `POST /whatsapp/templates/validate-media` — `apps/dashboard/pages/api/whatsapp/templates/validate-media.ts`

**`/zapi`**
- `GET /zapi/hasZapiProvider` — `apps/dashboard/pages/api/zapi/hasZapiProvider.ts`

**`/zapper`**
- `DELETE /zapper/instances/{}` — `apps/dashboard/pages/api/zapper/instances/[id].ts`
- `GET /zapper/instances` — `apps/dashboard/pages/api/zapper/instances/index.ts`
- `GET /zapper/instances/{}` — `apps/dashboard/pages/api/zapper/instances/[id].ts`
- `GET /zapper/instances/{}/connection` — `apps/dashboard/pages/api/zapper/instances/[id]/connection.ts`
- `GET /zapper/integrations` — `apps/dashboard/pages/api/zapper/integrations.ts`
- `PATCH /zapper/instances/{}` — `apps/dashboard/pages/api/zapper/instances/[id].ts`
- `POST /zapper/accounts` — `apps/dashboard/pages/api/zapper/accounts.ts`
- `POST /zapper/instances` — `apps/dashboard/pages/api/zapper/instances/index.ts`
- `POST /zapper/instances/db` — `apps/dashboard/pages/api/zapper/instances/db.ts`
- `POST /zapper/instances/webhook` — `apps/dashboard/pages/api/zapper/instances/webhook.ts`
- `POST /zapper/instances/{}/restart` — `apps/dashboard/pages/api/zapper/instances/[id]/restart.ts`


## 11. Testes ao vivo com chave de teste (2026-10-30)

Rodados com uma chave de teste fornecida pelo usuário no chat. Só leituras e requisições sem
efeito colateral: nenhum agente, base ou conversa foi criado, alterado ou apagado. A chave não foi
gravada em nenhum arquivo do repositório.

- `tests/smoke.sh --live`: 213 PASS, 0 FAIL, 1 SKIP (o caso que exige `CHATVOLT_AGENT_ID`).
- `agent-admin/scripts/check-handle.sh`: handle livre responde `disponível`; handle já usado responde `já usado pelo agente <id>`. Os dois casos ao vivo.
- `agent-admin/scripts/generate-prompt.sh`: gerou um `systemPrompt` coerente com os campos enviados (exit 0). Esta chamada consome a IA da organização.
- `GET /api/logs/{id}/assignment-history`: 200 em `api.chatvolt.ai` com um ID real de conversa; sem `/api`, 404.
- `POST /crm/card` e `POST /whatsapp/conversion-tracking` sem corpo: 400 de validação, prova de que as rotas existem.
- `POST /datastores/query/{id}/old`: 404 de página do Next.js, sem rota.
- `GET /conversation-event-log`, `GET /dispatches/contacts/link`: 404, coerentes com indisponível / não implementado.
- `GET /crm/step/{id}`, `GET /crm/scenario/{id}`, `POST /crm/scenario/{id}/conversation`: 404 com ID inventado. Teste inconclusivo, já que o mesmo 404 aparece para recurso inexistente. Sem arquivo de rota no código, a conclusão é "não implementado".
- `GET /agent-templates/{id}` com ID inventado: 404, esperado pela regra de organização de templates.
