---
name: chatvolt-agent-test
description: >
  Testa um agente Chatvolt de ponta a ponta: mostra a configuração, envia
  queries em conversa nova (ou continuando uma, com confirmação explícita),
  acompanha o stream SSE e monta a transcrição AGENT/HUMAN com as sources e as
  regras esperadas. Use para validar se o agente segue as instruções, testar
  cenários complexos ou depurar comportamento inesperado.
---

# Chatvolt Agent Testing

Você informa a API key, o ID do agente e as regras que o agente deveria seguir; eu mostro a configuração atual, envio as perguntas, guardo o `conversationId` e monto a transcrição (HUMAN/AGENT) com as sources usadas e as regras, para você comparar resposta por resposta.

> **Pré-requisitos:** chave de API (https://app.chatvolt.ai/settings/api-keys) e o ID do agente.

## Regra crítica: conversa existente exige `--force`

Mensagens enviadas por `POST /agents/{id}/query` com `conversationId` são **gravadas no histórico real da conversa** e podem aparecer para o cliente.

- **Preferir sempre uma conversa nova**: omita `--conversation` (o agente cria a conversa).
- `send-query.sh` **recusa** `--conversation` sem `--force`: avisa em stderr e **sai com código 2 sem chamar a API**.
- Conversas de teste criadas por `api` podem ser apagadas depois com a skill `chatvolt-conversation-cleanup`.

## Como funciona

1. **Configuração** — `get-agent.sh` lê `GET /agents/{id}` e `GET /agents/{id}/tools` e mostra nome, id, handle, modelo, temperatura, visibilidade, o system prompt completo e a tabela de tools.
2. **Envio** — `send-query.sh` monta o payload apenas com o que foi passado e chama `POST /agents/{id}/query`. Sem `--conversation`, uma conversa nova é criada; o `conversationId` retornado é impresso.
3. **Stream** — com `--stream`, o corpo vai com `streaming:true` e a saída é lida com `curl -N` (SSE).
4. **Transcrição** — `analyze-results.sh` busca as mensagens reais em `GET /conversation/{id}/messages/{n}`, imprime o system prompt do agente, a transcrição cronológica (HUMAN/AGENT), a contagem e as regras esperadas. **Nenhuma avaliação automática é feita** — não existe "análise por IA" inventada: a comparação é sua.
5. **Sessão interativa** — `test-agent.sh` encadeia tudo: config → fluxo esperado → conversa nova → loop pergunta/resposta com histórico e análise sob demanda.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents/{id}` | Configuração do agente (prompt, modelo, temperatura, visibilidade) |
| `GET` | `/agents/{id}/tools` | Lista de tools do agente (array na raiz) |
| `POST` | `/agents/{id}/query` | Envia a query; cria ou continua a conversa |
| `GET` | `/conversation/{id}/messages/{n}` | Últimas `n` mensagens da conversa |
| `GET` | `/conversation` | Lista conversas (filtros `agentId`, `channel`, `status`, `limit`…) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs: <https://chat-volt.mintlify.app/pages/agents/reference> (OpenAPI: <https://chat-volt.mintlify.app/openapi.yaml>)

### Parâmetros de `POST /agents/{id}/query`

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `query` | sim | Texto da pergunta |
| `conversationId` | não | Continua a conversa indicada; **grava no histórico real** |
| `streaming` | não | `true` devolve SSE (`send-query.sh --stream`) |
| `temperature` / `modelName` | não | Sobrescrevem temperatura/modelo do agente |
| `visitorId`, `contactId`, `contact{firstName,lastName,email,phoneNumber,userId}` | não | Identificação do visitante/contato |
| `systemPrompt` | não | System prompt válido só para esta query |
| `callbackURL` | não | URL chamada ao final da resposta |
| `filters{custom_ids,datasource_ids}` | não | Filtros de recuperação na base |

### Formato da resposta

A resposta volta **na raiz** (não existe `data.content`):

```json
{ "answer": "...", "sources": [ { "chunk_id": "...", "datastore_id": "...",
  "datasource_id": "...", "datasource_name": "...", "datasource_type": "file",
  "mime_type": "...", "score": 0.39769745 } ],
  "messageId": "...", "conversationId": "...", "visitorId": "..." }
```

Com `streaming:true`, o corpo é SSE:

```
event: endpoint_response
data: %7B%22messageId%22%3A...%7D

event:
data: [DONE]
```

O JSON do evento vem com URL-encoding — os scripts decodificam e imprimem o resultado final.

### `GET /conversation/{id}/messages/{n}`

Retorna `{status, isAiEnabled, userId, organizationId, participantsContacts, lastHumanInteractionAt, messages:[...]}`.
`messages` vem da **mais recente para a mais antiga** e cada item é `{id, text, from, read, attachments, createdAt, eval}` com `from` em `human|agent`.
`n` é o número máximo de mensagens pedidas (os scripts usam 200 e avisam quando o limite é atingido).
**Este endpoint não devolve `sources`** — para analisá-las, passe o JSON cru da query com `--sources`.
Conversa inexistente/apagada responde `null` com HTTP 200; os scripts detectam e explicam.

### Tools

Os tipos observados na organização incluem `http`, `datastore`, `follow_up_messages`, `delayed_responses`, `artifact_category_selector`, `mark_as_resolved`, `quick_reply_buttons` e `request_human`.
**Não existe `GET /agents/{id}/tools/{toolId}`** (responde 404) — para ver uma tool, filtre a listagem (skill `chatvolt-tools-update`).

### Erros e limites

`400`, `401`, `403`, `404`, `406` (sessão do canal expirada), `402` (quota do plano), `429` (60 req/min, 10.000/dia, com `Retry-After`), `5xx`.
Códigos de saída dos scripts: **0** ok · **1** erro de cliente · **2** uso indevido (`--conversation` sem `--force`) · **3** quota · **4** rede · **5** servidor · **130** cancelado.

## Scripts auxiliares

Estão em `scripts/` (rode com `bash scripts/<nome>.sh` ou via `chatvolt.sh agent-test <nome>.sh`).

- `get-agent.sh <api-key> <agent-id>` — configuração + system prompt + tabela de tools. `CV_JSON=1` ⇒ `{"agent":{...},"tools":[...]}`.
- `send-query.sh <api-key> <agent-id> <query> [opções]` — envia a query.
  `--conversation <id>` (exige `--force`), `--force`, `--temp <0.0-1.0>`, `--model <nome>`, `--visitor-id`, `--contact-id`, `--contact-first-name`, `--contact-email`, `--contact-phone`, `--system-prompt`, `--callback-url`, `--stream`.
  Imprime `answer`, `conversationId`, `messageId`, `visitorId` e as `sources`; `CV_JSON=1` ⇒ JSON cru.
- `analyze-results.sh <api-key> <agent-id> <conversation-id> [--expected "<regras>"] [--expected-file <f>] [--sources <json|@arquivo>] [--limit <n>]` — system prompt, transcrição cronológica, contagem, sources e regras esperadas. Sem julgamento automático.
- `test-agent.sh <api-key> <agent-id>` — sessão interativa. Comandos: `:continuar`, `:nova`, `:historico`, `:analisar`, `:sair`, `:ajuda`; qualquer outra linha é enviada como pergunta.

A api key também pode vir de `CHATVOLT_API_KEY`, dispensando o primeiro argumento. `CV_API_BASE` troca a base URL (usado pelos testes offline).
