---
name: chatvolt-dispatches
description: >
  Lista, cria, popula e remove disparos (campanhas em massa) do Chatvolt e
  gerencia as listas de contatos usadas por eles: listas, contatos e vínculos.
  Use para acompanhar o andamento de campanhas, montar/editar listas de
  contatos, conferir quem será disparado, vincular listas de inclusão/exclusão
  a um disparo e apagar campanhas ou listas.
---

# Chatvolt Dispatches (disparos e listas de contatos)

Você me diz qual campanha, lista ou contato quer olhar (ou o que quer criar,
vincular ou apagar), e eu executo a operação pela API do Chatvolt: listo os
disparos com as métricas de envio, gerencio as listas de contatos, confiro e
edito os contatos de cada lista, faço o vínculo disparo ↔ lista e removo
campanhas e listas com confirmação.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys).
> Para criar disparo: o `agentId` do agente responsável e, de preferência, os
> ids das listas de contatos. Para mexer em contatos: o `contactListId`.

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Regras críticas

1. **Disparo é campanha em massa.** `populate-queue.sh` coloca mensagens na
   fila e os envios acontecem de verdade para os contatos (WhatsApp/Telegram
   conforme a integração da organização). Ele exige `--yes` explícito —
   `CV_YES=1` **não** substitui esse flag.
2. `create-dispatch.sh` também exige `--yes` explícito: ele cria/altera a
   campanha (o envio só começa no `populate-queue`).
3. Nada de disparo ao vivo em teste: `create-dispatch.sh` e
   `populate-queue.sh` são validados apenas no stub offline.
4. **`GET /dispatches/contacts` exige `contactListId`**: sem ele a API responde
   `400 {"message":"Query must include 'contactListId'."}`.
5. **`GET /dispatches/{id}` não existe** (o path responde 404). Para inspecionar
   um disparo, varra a listagem `GET /dispatches`.
6. `DELETE /dispatches` com id inexistente responde **HTTP 500** com
   `{"error":"Dispatch not found or you do not have permission to delete it."}`
   (o openapi documenta 404). Por isso o `delete-dispatch.sh` confere a
   existência antes de apagar.

## Como funciona

1. Você informa a **API key** (argumento ou `CHATVOLT_API_KEY`).
2. **Listar disparos** com filtros de nome, status, agente, cenário/etapa de CRM
   e período, com paginação (`--all`).
3. **Montar a campanha**: crie o disparo (`create-dispatch.sh`), ajuste as
   listas (create/update/delete), adicione contatos (`list-contacts.sh add`) e
   vincule listas de inclusão/exclusão (`link-contacts.sh`).
4. **Disparar**: `populate-queue.sh <id> --yes` popula a fila; acompanhe por
   `list-dispatches.sh` (`sentCount`/`errorCount`/`latestErrorMessage`).
5. **Limpar**: apagar contato, lista ou o disparo inteiro, sempre com
   confirmação (`CV_YES=1` automatiza).

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/dispatches` | Lista disparos (`{dispatches:[...], count, totalCount?, sentCount?, errorCount?, latestErrorMessage?}`) |
| `POST` | `/dispatches` | Cria ou atualiza um disparo (`id` no corpo = atualizar) |
| `DELETE` | `/dispatches?id=<id>` | Deleta o disparo |
| `POST` | `/dispatches/{id}/populate-queue` | Popula a fila do disparo (inicia os envios reais) |
| `GET` | `/dispatches/contacts` | Lista contatos de uma lista (`contactListId` obrigatório) → `{contacts:[...], count}` |
| `POST` | `/dispatches/contacts` | Cria/atualiza um contato; aceita também um array (lote) |
| `DELETE` | `/dispatches/contacts?contactId=<id>` | Deleta um contato |
| `GET` | `/dispatches/contacts/{contactId}` | Contato individual (+ `contactList`) |
| `GET` | `/dispatches/contacts/lists` | Lista as listas de contatos → `{lists:[...], count}` |
| `POST` | `/dispatches/contacts/lists` | Cria ou atualiza uma lista (`id` no corpo = atualizar) |
| `PUT` | `/dispatches/contacts/lists` | Atualiza uma lista (rota dedicada) |
| `DELETE` | `/dispatches/contacts/lists?id=<id>` | Deleta a lista e todos os dados associados |
| `POST` | `/dispatches/contacts/link` | Vincula (ou exclui) uma lista em um disparo |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/dispatches/reference>

### Disponibilidade medida ao vivo (2026-10-12)

| Rota | Estado |
|---|---|
| `GET /dispatches` | disponível (`200`) |
| `GET /dispatches/contacts/lists` | disponível (`200`) — `{lists:[...],count}`, cada lista com `contactsCount` |
| `GET /dispatches/contacts?contactListId=` | disponível (`200`); sem `contactListId` → `400` |
| `GET /dispatches/contacts/{contactId}` | disponível (`200`); inexistente → `404 {"error":"Contact not found"}` |
| `DELETE /dispatches?id=<inexistente>` | responde **`500`** (a doc diz 404) |
| `GET /dispatches/{id}` | **não existe** — o path devolve `404` (HTML do dashboard) |
| `POST /dispatches`, `POST /dispatches/{id}/populate-queue` | rota de **envio real** — nunca disparadas em teste ao vivo |
| `POST`/`PUT`/`DELETE /dispatches/contacts/lists`, `POST`/`DELETE /dispatches/contacts`, `POST /dispatches/contacts/link` | mutações validadas no stub offline |

### Campos e parâmetros

- `GET /dispatches`: `offset` (0), `limit` (100), `search`, `status`, `agentId`,
  `crmScenarioId`, `crmStepId`, `startDate`, `endDate` (ISO 8601),
  `archived` (bool). A resposta real traz `dispatches` + `count` na raiz (os
  campos `totalCount`/`sentCount`/`errorCount`/`latestErrorMessage` aparecem
  quando existem; um campo ausente é exibido como `?` na tabela).
- Objeto do disparo: `id`, `name`, `status`, `agentId`, `crmScenarioId`,
  `crmStepId`, `scheduledAt`, `templateMessage` (pode ser **string JSON** de um
  template de WhatsApp), `interval`, `createdAt`, `updatedAt` (e, em disparos
  reais, `defaultAssigneeId`, `defaultStatus`, `defaultTags`, `organizationId`).
- `POST /dispatches` (`DispatchPayload`): `name` e `agentId` são os campos que o
  script exige; aceita também `id` (upsert), `status`, `crmScenarioId`,
  `crmStepId`, `scheduledAt`, `templateMessage`, `interval` (minutos),
  `contactListIds[]`, `exclusionContactListIds[]`, `defaultAssigneeId`,
  `defaultStatus`.
- `GET /dispatches/contacts/lists`: `offset` (0), `limit` (100), `search`.
  Objeto da lista: `id`, `name`, `contactsCount`, `createdAt`, `updatedAt`,
  `organizationId`.
- `GET /dispatches/contacts`: `contactListId` (**obrigatório**), `offset` (0),
  `limit` (100), `search`. Objeto do contato: `id`, `name`, `phoneNumber`,
  `contactListId`, `createdAt`, `updatedAt`.
- `POST /dispatches/contacts`: um contato
  (`{id?, name, phoneNumber, contactListId}`) **ou** um array de contatos
  (`--bulk`; os itens levam `name`/`phoneNumber` — inclua `contactListId` em
  cada item quando a API exigir).
- `POST /dispatches/contacts/link`: `{dispatchId, contactListId, isExcluded}`
  — `isExcluded: true` marca a lista como **exclusão** do disparo.

### Limites e erros

Rate limit **60 req/min** e **10.000 req/dia**; payload máximo **1 MB**. Um
`429` é reprocessado com backoff pelo helper HTTP (`CV_MAX_RETRIES`,
`CV_RETRY_WAIT`). Códigos tratados: `400`, `401`, `402` (quota do plano → exit
3), `403`, `404`, `406`, `429`, `5xx`.

## Scripts auxiliares

- `scripts/list-dispatches.sh <api-key> [--search T] [--status S] [--agent ID] [--crm-scenario ID] [--crm-step ID] [--start-date D] [--end-date D] [--archived] [--limit N] [--offset N] [--all]`
  — lista os disparos em tabela (id, nome, status, agente, agendamento,
  enviados/total, erros) e repete a última mensagem de erro de cada campanha.
- `scripts/create-dispatch.sh <api-key> --name N --agent ID [--id ID] [--status S] [--crm-scenario ID] [--crm-step ID] [--scheduled-at ISO] [--template-message T] [--interval MIN] [--contact-list ID]… [--exclude-list ID]… [--json '<extra>'] --yes`
  — cria (ou atualiza, com `--id`) o disparo. **Exige `--yes`** e avisa que é
  uma campanha em massa.
- `scripts/delete-dispatch.sh <api-key> <dispatch-id> [--force]`
  — confere o disparo na listagem (mostra nome/status), pede confirmação e
  executa `DELETE /dispatches?id=…`. `--force` pula a checagem.
- `scripts/populate-queue.sh <api-key> <dispatch-id> --yes`
  — popula a fila do disparo (envios reais). **Exige `--yes`**.
- `scripts/contact-lists.sh <api-key> list|create|update|delete …`
  — `list [--search T] [--limit N] [--offset N] [--all]`,
  `create --name N`,
  `update <id> --name N [--post]` (usa a rota dedicada `PUT`; com `--post` faz o
  upsert pelo `POST`; pede confirmação, pulável com `CV_YES=1`),
  `delete <id>` (confirmação).
- `scripts/list-contacts.sh <api-key> [list|get|add|delete] …`
  — `list --list <contactListId> [--search T] [--limit N] [--offset N] [--all]`,
  `get <contactId>`, `add --list ID --name N --phone P [--id ID]` ou
  `add --bulk arquivo.json`, `delete <contactId>` (confirmação; busca o contato
  antes).
- `scripts/link-contacts.sh <api-key> --dispatch ID --list ID [--exclude]`
  — vincula a lista ao disparo como inclusão (padrão) ou exclusão.

Saída: resultados em **stdout**, diagnósticos em **stderr**. Com `CV_JSON=1` o
stdout contém **somente JSON**.

## Exemplos

```bash
# Campanhas em andamento e falhas
./dispatches/scripts/list-dispatches.sh "$CHATVOLT_API_KEY" --limit 20
./dispatches/scripts/list-dispatches.sh "$CHATVOLT_API_KEY" --status COMPLETED --all

# Listas de contatos
./dispatches/scripts/contact-lists.sh "$CHATVOLT_API_KEY" list --limit 50
./dispatches/scripts/contact-lists.sh "$CHATVOLT_API_KEY" create --name "Leads Outubro"

# Contatos de uma lista
LIST=30eead17-5b26-4b8d-a82b-e51dff8740f0
./dispatches/scripts/list-contacts.sh "$CHATVOLT_API_KEY" --list "$LIST" --limit 20
./dispatches/scripts/list-contacts.sh "$CHATVOLT_API_KEY" add --list "$LIST" --name "Fulano" --phone 5511900000000

# Montar e disparar (campanha em massa — só com --yes)
./dispatches/scripts/create-dispatch.sh "$CHATVOLT_API_KEY" --name "Campanha Outubro" \
  --agent "$CHATVOLT_AGENT_ID" --contact-list "$LIST" --template-message "Olá!" --yes
./dispatches/scripts/link-contacts.sh "$CHATVOLT_API_KEY" --dispatch "$DISPATCH_ID" --list "$LIST"
./dispatches/scripts/populate-queue.sh "$CHATVOLT_API_KEY" "$DISPATCH_ID" --yes

# Limpeza (com confirmação; CV_YES=1 em automação)
./dispatches/scripts/delete-dispatch.sh "$CHATVOLT_API_KEY" "$DISPATCH_ID"
./dispatches/scripts/contact-lists.sh "$CHATVOLT_API_KEY" delete "$LIST"
```
