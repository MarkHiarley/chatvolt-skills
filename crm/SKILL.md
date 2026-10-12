---
name: chatvolt-crm
description: >
  Gerencia o Flux CRM do Chatvolt pela API: cenários (funis), etapas, vínculo
  de conversas com cenário/etapa, logs de conversa, contagem de conversas por
  cenário e eventos em tempo real (SSE). Use para montar um funil de CRM, mover
  conversas entre etapas, auditar a passagem das conversas pelo funil ou
  escutar eventos do CRM.
---

# Chatvolt CRM (Flux CRM)

Você me diz qual cenário, etapa, conversa ou log quer olhar (ou alterar), e eu
executo a operação pela API do Chatvolt: cenários (pipelines), etapas (steps),
vínculo de conversas com etapas, logs de atividade, contagens e o stream de
eventos do CRM.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys).
> Quase tudo exige um `scenarioId` (de `GET /crm/scenario`) e, para vínculos,
> um `stepId` (de `GET /crm/step?scenarioId=…`).

## Como funciona

1. Você informa a **API key** (1º argumento ou `CHATVOLT_API_KEY`).
2. **Cenários** (`scenarios.sh`): listar (com filtro `agentId`), criar, renomear
   e apagar. Não existe `GET /crm/scenario/{id}` — o script filtra a listagem.
3. **Etapas** (`steps.sh`): listar por cenário, criar (a API exige `trigger` ou
   `prompt`), atualizar e apagar. O `id` das etapas vai no **corpo** do PUT/DELETE.
4. **Vínculos** (`step-conversations.sh`): listar as conversas de um cenário,
   contar por etapa (`isCount`), adicionar uma conversa a uma etapa, mover a
   conversa de etapa e desvincular a conversa do cenário.
5. **Logs** (`conversation-logs.sh`): listar (trilha de auditoria do funil),
   obter, criar e atualizar o `status` (PUT/PATCH) ou apagar um log.
6. **Contagem** (`count.sh`): total de conversas do cenário.
7. **Eventos** (`events.sh`): escuta `GET /crm/events` (SSE) do cenário informado em
   `--scenario` (obrigatório) e imprime os eventos recebidos; encerra limpo ao fim
   do `--max-time` (padrão 30s).

Operações que alteram estado pedem confirmação (`CV_YES=1` ou `--yes` pula).

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/crm/scenario` | Lista cenários (filtro `agentId`) |
| `POST` | `/crm/scenario` | Cria cenário (`name`, `description`) |
| `PUT` | `/crm/scenario` | Atualiza cenário (`id` + `name` no corpo) |
| `DELETE` | `/crm/scenario` | Apaga cenário (`id` no corpo) |
| `GET` | `/crm/step` | Lista etapas do cenário (`scenarioId` obrigatório) |
| `POST` | `/crm/step` | Cria etapa (`scenarioId`, `name` + `trigger`/`prompt`) |
| `PUT` | `/crm/step` | Atualiza etapa (`id` + `name` no corpo) |
| `DELETE` | `/crm/step` | Apaga etapa (`id` no corpo) |
| `POST` | `/crm/step/conversation` | Adiciona a conversa a uma etapa |
| `POST` | `/crm/step/move` | Move a conversa para outra etapa |
| `GET` | `/crm/scenario/{scenarioId}/conversation` | Lista conversas do cenário (ou contagens com `isCount`) |
| `DELETE` | `/crm/scenario/{scenarioId}/conversation` | Desvincula a conversa do cenário (`?conversationId=`) |
| `GET` | `/crm/conversationLog` | Lista logs (paginado) |
| `POST` | `/crm/conversationLog` | Cria log de atividade |
| `GET` | `/crm/conversationLog/{logId}` | Objeto do log |
| `PUT` / `PATCH` | `/crm/conversationLog/{logId}` | Atualiza o `status` do log |
| `DELETE` | `/crm/conversationLog/{logId}` | Apaga o log |
| `GET` | `/crm/conversation/count` | Total de conversas do cenário |
| `GET` | `/crm/events` | Eventos do CRM em tempo real (SSE) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/crm/reference> (índice em
<https://chat-volt.mintlify.site/llms-full.txt>).

### Formas reais das respostas (medidas ao vivo em 2026-10-12)

| Rota | Forma real |
|------|------------|
| `GET /crm/scenario` | **array na raiz** (`id`, `name`, `description`, `showInactiveConversations`, `allowedUserIds`, `createdAt`, `updatedAt`) |
| `POST/PUT/DELETE /crm/scenario` | objeto do cenário **na raiz** (`POST` → `201`) |
| `GET /crm/step?scenarioId=…` | **array na raiz** (`id`, `index`, `name`, `trigger`, `prompt`, `initialMessage`, `autoNextStepId/Time/Unit`, `defaultStatus`, `defaultPriority`, `assigneeLogicType`, `isRequired`, …) |
| `POST/PUT/DELETE /crm/step` | objeto da etapa **na raiz** |
| `GET /crm/scenario/{id}/conversation` | **array na raiz** (`available`, `order`, `conversationId`, `stepId`, `step`, `conversation`) |
| `GET …?isCount=true` | **mapa `{stepId: quantidade}`**; com `&stepId=…` → **`{"count": N}`** |
| `DELETE /crm/scenario/{id}/conversation` | `{"message": "Conversation successfully removed from scenario"}` |
| `GET /crm/conversationLog` | **`{"data":[…],"pagination":{"page","limit","total","totalPages"}}`** |
| `GET/PUT/PATCH /crm/conversationLog/{logId}` | objeto do log na raiz (traz `conversation`, `scenario`, `step` aninhados) |
| `DELETE /crm/conversationLog/{logId}` | `{"message": "Log deleted successfully"}` |
| `GET /crm/conversation/count?scenarioId=…` | **`{"total": N}`** na raiz |
| `GET /crm/events` | `text/event-stream`; primeiro evento `data: {"type":"CONNECTED","channel":"crm:<orgId>:<scenarioId>"}` |

As páginas narrativas da doc mostram um envelope `{data, success, error}` — **ao
vivo ele não existe** nessas rotas (o `openapi.yaml` está mais próximo do real).

### Parâmetros e contratos

**Cenários.** `name` é obrigatório no `POST`; `id` + `name` no `PUT`; só `id` no
`DELETE` (sempre no **corpo**, não há path param). `403` quando o limite de
cenários do plano é atingido. Apagar um cenário remove etapas e vínculos.

**Etapas.** `GET /crm/step` **exige `scenarioId`**: sem ele o servidor responde
`500 {"error":"scenario ID is required"}` (por isso o script valida antes). O
`POST` exige `scenarioId` + `name` e declara `oneOf(trigger, prompt)` — envie ao
menos um (`trigger` e `prompt` juntos podem ser recusados). Campos opcionais
aceitos: `agentId`, `initialMessage`, `autoNextStepId`, `autoNextTime` +
`autoNextTimeUnit` (`m|h|d`), `defaultStatus` (`RESOLVED|UNRESOLVED|HUMAN_REQUESTED`),
`defaultPriority` (`LOW|MEDIUM|HIGH`), `assigneeLogicType`
(`none|clear|single_user|random_selected|fair_distribution_selected`),
`selectedMembershipIdsForAssignee`, `isRequired`, `defaultTags`,
`defaultTagsToRemove`, `requestContact{name,email,phone}`,
`isConversationRemovalStep`, campos `zapi*`/`whatsappTemplate*`, `defaultAiControl`,
`webhookUrl`, `webhookHeader`. O `PUT` exige `id` + `name` e aceita `null` para
limpar campos (`autoNextStepId`, `autoNextTime`, `agentId`, …); o `DELETE` recebe
só `id`. `403` quando o limite de etapas do plano é atingido.

**Vínculo de conversas.** `POST /crm/step/conversation` recebe `conversationId` e
identifica a etapa por `stepId` **ou** `stepIndex` (o índice é relativo ao
`scenarioId`, que vira obrigatório nesse caso). `POST /crm/step/move` recebe
`conversationId` + `destStepId` (ou `destStepIndex` com `scenarioId`); se
`scenarioId` e `destStepId` vierem juntos, precisam ser coerentes.
`GET /crm/scenario/{id}/conversation` aceita `stepId`, `page` (padrão `0`),
`limit`, `isCount` e `showInactiveConversations`; cenário inexistente → `404`.
`DELETE …?conversationId=…` desvincula (não apaga a conversa).

**Logs.** `GET /crm/conversationLog` filtra por `conversationId`, `scenarioId`,
`stepId`, `status` (`inactive|active|error`), `page` (≥ 1) e `limit` (1–100,
padrão 10). O `POST` exige `conversationId`, `scenarioId`, `stepId` e `status`.
No `PUT`/`PATCH /crm/conversationLog/{logId}` só `status` é atualizável — os dois
métodos são funcionalmente idênticos hoje.

**Contagem.** `GET /crm/conversation/count` devolve `{"total": N}` e **exige
`scenarioId`** (`400 {"error":"scenarioId is required"}` sem ele; cenário
inexistente → `404 {"error":"Scenario not found"}`). O parâmetro `stepId` é
**aceito mas ignorado**: verificado ao vivo com dois steps distintos e um id
inexistente, todos devolvendo o total do cenário. Para contagem **por etapa** use
`step-conversations.sh count <cenário> --step <etapa>` (`isCount=true`).

**Eventos (SSE).** `GET /crm/events?scenarioId=…` responde `text/event-stream` e
mantém a conexão aberta indefinidamente (sem tráfego quando não há atividade no
CRM). O `scenarioId` é **obrigatório**: sem ele a rota responde na hora
`400 {"error":"scenarioId is required"}` (medido ao vivo — o `openapi.yaml` não
declara parâmetro nenhum nessa rota e a página da doc está vazia). Cada evento vem como um objeto JSON em uma linha `data:` (o script ignora
`event:`/`id:`/comentários). Por isso `events.sh` usa `curl -N` com `--max-time`
e encerra com **exit 0** quando o tempo acaba (curl 28) ou o servidor fecha o
stream. Para acompanhar continuamente, aumente `--max-time`; para encerrar antes,
Ctrl+C (exit 130).

### Disponibilidade e limites

- Todas as rotas de CRM estão **disponíveis** na organização de teste (2026-10-12),
  exceto as de escrita, que foram validadas só contra o stub/contrato.
- Rate limit: **60 req/min** e **10.000 req/dia** (payload máx. 1 MB); `429` é
  reprocessado com backoff pelo helper HTTP.
- Códigos tratados: `400`, `401`, `402` (quota do plano), `403` (limite de
  cenários/etapas), `404`, `406`, `429`, `5xx`.
- Exit codes: `0` ok · `1` erro de cliente · `3` quota (402) · `4` rede ·
  `5` servidor · `130` cancelado.

## Scripts auxiliares

- `scripts/scenarios.sh <api-key> list|show|create|update|delete …`
  — `list [--agent <id>]` · `show <scenario-id> [--agent <id>]` ·
  `create --name "<nome>" [--description "<txt>"] [--json '<extra>']` ·
  `update <scenario-id> --name "<nome>" [--description "<txt>"] [--json '<extra>']`
  · `delete <scenario-id> [--yes]` (mostra o cenário antes de apagar).
- `scripts/steps.sh <api-key> list|show|create|update|delete …`
  — `list <scenario-id> [--agent <id>]` · `show <step-id> --scenario <id>` ·
  `create <scenario-id> --name "<nome>" (--trigger "<t>" | --prompt "<p>") [--initial-message] [--agent] [--default-status] [--default-priority] [--assignee-logic] [--auto-next-step] [--auto-next-time] [--auto-next-unit] [--required|--not-required] [--json '<extra>']`
  · `update <step-id> --name "<nome>" [mesmas opções]` (sem `--name`, reaproveita
  o nome atual quando `--scenario` é informado) · `delete <step-id> [--scenario <id>] [--yes]`.
- `scripts/step-conversations.sh <api-key> list|count|add|move|remove …`
  — `list <scenario-id> [--step <id>] [--page <n>] [--limit <n>] [--inactive]` ·
  `count <scenario-id> [--step <id>]` · `add <scenario-id> <conversation-id> (--step <id> | --step-index <n>)`
  · `move <conversation-id> (--dest-step <id> | --dest-step-index <n>) [--scenario <id>]`
  · `remove <scenario-id> <conversation-id> [--yes]`.
- `scripts/conversation-logs.sh <api-key> list|get|create|update|patch|delete …`
  — `list [--conversation <id>] [--scenario <id>] [--step <id>] [--status <s>] [--page <n>] [--limit <n>]`
  · `get <log-id>` · `create --conversation <id> --scenario <id> --step <id> [--status <s>]`
  · `update <log-id> --status <s>` (PUT) · `patch <log-id> --status <s>` (PATCH) ·
  `delete <log-id> [--yes]`.
- `scripts/count.sh <api-key> <scenario-id> [--step <step-id>]`
  — total de conversas do cenário (`--step` é aceito e avisa que a rota o ignora).
- `scripts/events.sh <api-key> --scenario <scenario-id> [--max-time <s>] [--raw]`
  — escuta o SSE e imprime `[n] TIPO {json}` (ou NDJSON com `CV_JSON=1`, ou os
  bytes crus com `--raw`); o resumo vai para stderr.

Saída: resultados em **stdout**, diagnósticos em **stderr**. Com `CV_JSON=1` o
stdout contém **somente JSON** (em `events.sh`, um objeto por linha).

## Exemplos

```bash
./crm/scripts/scenarios.sh "$CHATVOLT_API_KEY" list --agent "$CHATVOLT_AGENT_ID"
./crm/scripts/scenarios.sh "$CHATVOLT_API_KEY" create --name "Funil de Vendas" --description "Leads inbound"
./crm/scripts/steps.sh "$CHATVOLT_API_KEY" list cmpwwpn1r04hl12pfoglarith
./crm/scripts/steps.sh "$CHATVOLT_API_KEY" create "$SC" --name "Qualificação" --prompt "Pergunte o segmento"
./crm/scripts/count.sh "$CHATVOLT_API_KEY" "$SC"
./crm/scripts/step-conversations.sh "$CHATVOLT_API_KEY" count "$SC" --step "$ST"
./crm/scripts/step-conversations.sh "$CHATVOLT_API_KEY" move "$CONV" --dest-step "$ST2" --scenario "$SC"
./crm/scripts/conversation-logs.sh "$CHATVOLT_API_KEY" list --scenario "$SC" --limit 5
./crm/scripts/conversation-logs.sh "$CHATVOLT_API_KEY" update "$LOG" --status inactive
./crm/scripts/events.sh "$CHATVOLT_API_KEY" --scenario "$SC" --max-time 30
CV_JSON=1 ./crm/scripts/events.sh "$CHATVOLT_API_KEY" --scenario "$SC" --max-time 5   # NDJSON
```
