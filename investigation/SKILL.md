---
name: chatvolt-investigation
description: >
  Investiga agentes Chatvolt sem alterar nada: lê a configuração (system prompt,
  modelo, temperatura, ferramentas), lista conversas com filtros e paginação por
  cursor, e recupera a transcrição de conversas. Use quando precisar auditar o
  comportamento de um agente ou analisar conversas já existentes.
---

# Chatvolt — Investigation

Investiga agentes Chatvolt. Você me diz **o que quer investigar** — configuração do agente, conversas recentes, mensagens de uma conversa — e eu busco e organizo as informações. Operação **somente leitura**: nada é criado, alterado ou apagado (a única exceção é `test-query.sh`, que envia uma pergunta e por isso cria uma conversa de teste; o script lembra como apagá-la).

> **Pré-requisitos:** chave de API do Chatvolt (https://app.chatvolt.ai/settings/api-keys) e o ID do agente.

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Como funciona

1. Você informa a **API key** e o **ID do agente** (a key pode vir de `CHATVOLT_API_KEY` e o id de `CHATVOLT_AGENT_ID`).
2. Me diz o que quer investigar:
   - **Configuração do agente** — system prompt, modelo, temperatura, tools;
   - **Conversas recentes** — lista com filtros (status, canal, etiqueta, IA, prioridade, atendente, não lidas) e paginação opcional;
   - **Mensagens de uma conversa** — transcrição com a origem de cada mensagem (`human` ou `agent`);
   - **Relatório completo** — config + conversas + mensagens + próximos passos.
3. Se quiser saber se o agente **segue** o prompt, o relatório aponta as evidências (respostas, fontes) — não há análise inventada por heurística.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents/{id}` | Detalhes do agente (objeto na raiz) |
| `GET` | `/agents/{id}/tools` | Ferramentas do agente (array na raiz) |
| `GET` | `/conversation` | Lista conversas com filtros (array na raiz) |
| `GET` | `/conversation/{id}/messages/{count}` | Mensagens da conversa |
| `POST` | `/agents/{id}/query` | Envia uma query de teste (cria conversa) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs: <https://chat-volt.mintlify.app/pages/conversations/reference> e <https://chat-volt.mintlify.app/pages/agents/reference>

### Filtros de `GET /conversation`

| Parâmetro | Valores / observações |
|---|---|
| `agentId` | ID do agente (aceita a string `null`) |
| `createdAt` | data inicial (ISO 8601) |
| `endDate` | data final (ISO 8601) |
| `status` | `RESOLVED` · `UNRESOLVED` · `HUMAN_REQUESTED` |
| `channel` | canal: `whatsapp`, `telegram`, `instagram`, `api`, `webchat`, … |
| `tag` | etiqueta da conversa |
| `ai` | `enabled` · `disabled` |
| `priority` | `LOW` · `MEDIUM` · `HIGH` |
| `assigneeId` | ID do atendente, ou `unassigned` |
| `unread` | conversas com mensagens não lidas |
| `adSourceId`, `crmScenarioId`, `crmStepId` | CRM / origem de anúncio |
| `frustrationMin` / `frustrationMax` | faixa de frustração |
| `npsStep`, `npsRating`, `npsRatingMin`, `npsRatingMax`, `npsCompleted` | NPS |
| `limit` | itens por página; **padrão 25, máximo 100** |
| `cursor` | paginação: JSON URL-safe `{"lastCreatedAt":"...","lastId":"..."}` |

`organizationId` **não é** parâmetro de listagem — ele só aparece como campo da própria conversa. Os scripts validam `--status` (`RESOLVED|UNRESOLVED|HUMAN_REQUESTED`), `--priority` (`LOW|MEDIUM|HIGH`) e `--limit` (1..100) **antes** de chamar a API, evitando o `400`.

### Resposta de `GET /conversation/{id}/messages/{count}`

```json
{ "status": "UNRESOLVED", "isAiEnabled": true, "userId": null,
  "organizationId": "...", "participantsContacts": [...],
  "lastHumanInteractionAt": "...",
  "messages": [ { "id": "...", "text": "...", "from": "human|agent",
                  "createdAt": "...", "attachments": [] } ] }
```

O campo `from` indica a origem da mensagem: `human` (contato/atendente) ou `agent` (IA).

### `POST /agents/{id}/query`

Envia `{ "query": "...", "streaming": false, "temperature"?: 0..1, "modelName"?: "..." }`. A resposta vem **na raiz**: `{answer, sources, messageId, conversationId, visitorId}`. Cada chamada cria uma conversa real no histórico do agente.

### Limites e erros

Rate limit de **60 req/min** e **10.000 req/dia**; payload máximo de **1 MB**; erros `400`, `401`, `402` (quota), `403`, `404`, `406`, `429`, `5xx` são tratados pelos scripts com mensagens acionáveis.

## Scripts auxiliares

- `scripts/agent.sh <api-key> <agent-id>` — objeto completo do agente (JSON formatado; `CV_JSON=1` devolve o JSON cru).
- `scripts/list-conversations.sh <api-key> <agent-id> [--days N] [--limit N≤100] [--status S] [--channel C] [--tag T] [--ai enabled|disabled] [--priority P] [--assignee A] [--unread] [--all] [--cursor JSON]` — tabela (id, canal, status, criação, contato do 1º `participantsContacts` e um marcador de IA quando `isAiEnabled`); `--all` pagina por cursor até o fim e avisa quando termina.
- `scripts/get-messages.sh <api-key> <conversation-id> [count]` — metadados + transcrição com `[HUMAN]`/`[AGENT]`.
- `scripts/test-query.sh <api-key> <agent-id> <query> [temperature] [model]` — envia uma query, imprime `answer` + `conversationId` e o lembrete de como apagar a conversa de teste.
- `scripts/investigate.sh <api-key> <agent-id> [days] [limit]` — relatório completo: configuração + conversas recentes + mensagens + próximos passos (`CV_JSON=1` devolve tudo em um único JSON).

### Variáveis de ambiente

| Variável | Efeito |
|---|---|
| `CHATVOLT_API_KEY` | API key (alternativa ao 1º argumento) |
| `CHATVOLT_AGENT_ID` | ID do agente padrão |
| `CV_JSON=1` | stdout contém **somente JSON**; diagnósticos vão para stderr |
| `CV_API_BASE` | base URL alternativa (usada pelo stub de teste) |
| `CV_TIMEOUT` | timeout do curl em segundos (padrão 120) |

Exit codes: `0` ok · `1` erro de cliente · `3` quota (402) · `4` rede · `5` servidor · `130` cancelado.
