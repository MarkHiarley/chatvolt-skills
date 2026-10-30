---
name: chatvolt-conversation-actions
description: >
  Executa ações em conversas do Chatvolt pela API: atribuir/desatribuir
  atendente, mudar status e prioridade, ligar/desligar a IA, notas internas,
  variáveis de conversa, etiquetas (indisponíveis via API key), registrar
  evento sem enviar, enviar mensagem/áudio (envio real, exige --yes), exportar
  a conversa em arquivo e consultar o histórico. Use quando precisar operar
  uma conversa existente (não para listar ou apagar conversas).
---

# Chatvolt Conversation Actions

Você me diz qual conversa e qual ação quer aplicar (atribuir a um atendente,
mudar status/prioridade, desligar a IA, deixar uma nota, gravar uma variável,
exportar o histórico), e eu executo pela API — sempre lendo a conversa antes
de escrever quando o risco justifica.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys)
> e o `id` da conversa. Para atribuir, o e-mail/id/membership do atendente;
> para exportar, um caminho de arquivo (`--out`).

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Como funciona

1. Você informa a **API key** (1º argumento ou `CHATVOLT_API_KEY`) e o
   **id da conversa** (veja as conversas em `GET /conversation` com a skill
   `chatvolt-conversation-cleanup`).
2. **Ações de estado**: `assign.sh`, `unassign.sh`, `set-status.sh`,
   `set-priority.sh`, `set-ai-enabled.sh` — cada uma pede confirmação
   (`CV_YES=1` ou `--yes` pula) porque alteram uma conversa real.
3. **Notas e variáveis**: `notes.sh` (list/create/update/delete via `--action`)
   e `variables.sh` (list/get/set/delete) — as notas são internas e as
   variáveis alimentam o contexto que o agente consulta.
4. **Registro sem envio**: `message-register.sh` grava um evento no contexto
   da conversa; o cliente **não** recebe nada.
5. **Envio real** (mensagem/áudio): `send-message.sh` e `send-audio.sh`
   **exigem `--yes`** e imprimem um aviso — a mensagem/áudio chega ao cliente
   final. Nunca use esses dois em teste automatizado.
6. **Leituras**: `tags.sh` (400/401 neste ambiente — ver abaixo),
   `export-conversation.sh` (arquivo binário via `--out`) e `history.sh`.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `POST` | `/conversations/{id}/assign` | Atribui a conversa a um atendente (`email`/`id`/`membershipId`, `force`) |
| `POST` | `/conversations/{id}/unassign` | Remove o atendente atual |
| `POST` | `/conversations/{id}/set-status` | `RESOLVED` \| `UNRESOLVED` \| `HUMAN_REQUESTED` |
| `POST` | `/conversations/{id}/set-priority` | `LOW` \| `MEDIUM` \| `HIGH` |
| `POST` | `/conversations/{id}/set-ai-enabled` | `{enabled: true|false}` |
| `GET` | `/conversations/{id}/notes` | Lista as notas **não privadas** (array na raiz) |
| `POST` | `/conversations/{id}/notes` | Cria nota (`note`, `isPrivate`, `isJustify`, `notificationDateTime`) → 201 |
| `PUT` | `/conversations/{id}/notes/{noteId}` | Atualiza a nota |
| `DELETE` | `/conversations/{id}/notes/{noteId}` | Apaga a nota → 204 (corpo vazio) |
| `GET` | `/conversations/{id}/tags` | **401 com API key** (exige sessão do dashboard) |
| `POST` | `/conversations/{id}/tags` | **401 com API key** (`{"tagName": "..."}`) |
| `POST` | `/variables` | Cria/atualiza (upsert) variável de conversa |
| `GET` | `/variables/{conversationId}` | Lista as variáveis da conversa (array na raiz) |
| `GET` | `/variables/{conversationId}/{varName}` | Lê uma variável (objeto na raiz) |
| `DELETE` | `/variables/{conversationId}/{varName}` | Apaga a variável |
| `POST` | `/conversations/{id}/message-register` | Registra mensagem **sem enviar** (`message`, `from: human\|agent`) |
| `POST` | `/conversation/message/{type}/{value}` | **ENVIO REAL** — `type` = `conversationId` \| `phone` \| `email` |
| `POST` | `/conversations/{id}/send-audio` | **ENVIO REAL** de áudio (`audioUrl`, `duration`) |
| `GET` | `/conversations/{id}/export` | **Binário** (planilha xlsx) — salvar com `--out` |
| `GET` | `/conversations/history?email=&agentId=` | Histórico de conversas (filtros obrigatórios) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/conversations/reference>

### Disponibilidade (medida ao vivo em 2026-10-12)

| Rota | Estado real |
|------|-------------|
| `/conversations/{id}/assign`, `/unassign`, `/set-status`, `/set-priority`, `/set-ai-enabled` | disponível |
| `/conversations/{id}/notes` (GET/POST/PUT/DELETE) | disponível |
| `/variables`, `/variables/{conversationId}[/{varName}]` | disponível |
| `/conversations/{id}/export` | disponível — `200` com `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` |
| `/conversations/history` | disponível — exige `email` **e** `agentId` na query |
| `/conversations/{id}/tags` (GET/POST) | **401** — a API exige a sessão do dashboard (cookie), não aceita API key |
| `/conversations/export` (exportação em lote) | **404** neste ambiente |

### Etiquetas de conversa: 401, não é a sua chave

`GET`/`POST /conversations/{id}/tags` respondem
`401 {"error":"Usuário não autenticado ou organização não encontrada."}` mesmo
com uma API key válida (verificado ao vivo). O `tags.sh` detecta esse caso e
explica, em vez de sugerir que a chave está errada. Enquanto isso, as etiquetas
de conversa continuam disponíveis no **dashboard** e podem ser usadas como
filtro em `GET /conversation?tag=<nome>` (skill `chatvolt-conversation-cleanup`).
Etiquetas de **base** (datastore) são outro recurso: skill
`chatvolt-datastore-tags`.

### Notas: privacidade e limites

- `GET /conversations/{id}/notes` devolve **somente as notas não privadas**
  (verificado ao vivo: uma nota criada com `isPrivate: true` não aparece na
  listagem, mas o `POST` devolve `201` com o objeto completo).
- `note` tem limite de **500 caracteres** (validado no script antes de chamar a
  API); `isJustify` só é aceito para admin.
- `DELETE` responde **204 sem corpo** — o script trata isso e informa sucesso.

### Variáveis de conversa: limites do contrato

`conversationId` até 50, `varName` até 20 e `varValue` até 100 caracteres — os
três limites são validados localmente (exit 1) antes da chamada. `POST /variables`
é **upsert**: mesmo `varName` na mesma conversa atualiza o `varValue`.
`GET /variables/{conversationId}` devolve array na raiz; `GET` da variável
específica devolve o objeto (404 quando não existe).

### `history.sh`: filtros obrigatórios

`GET /conversations/history` exige `email` **e** `agentId` **na query string**.
Sem eles a API responde `400 {"error":"Invalid request body (validation failed)",
"details":{"email":{"_errors":["Required"]},"agentId":{"_errors":["Required"]}}}`;
enviar os filtros no corpo também falha. A resposta é
`{"conversations":[...],"nextCursor":<token|null>,"email":"...","agentId":"..."}`.

### Envio real (mensagem e áudio)

- `POST /conversation/message/{type}/{value}` identifica o destinatário por
  `conversationId`, `phone` ou `email`. Se `type` **não** for `conversationId`,
  a API exige `agentId` ou `channel` no corpo (sem eles: `400 INVALID_REQUEST`).
  Anexos vão em `attachments[]` (`url`, `name`, `mimeType`).
- `POST /conversations/{id}/send-audio` recebe `audioUrl` (URL **pública**, o
  Chatvolt baixa o arquivo; evite > 16 MB) e `duration` em segundos.
- Nos dois scripts o `--yes` é **obrigatório** e um aviso explícito é impresso
  antes da chamada: a mensagem chega ao **cliente real**. Sem `--yes` o script
  sai com exit 1 e não chama a API. Em teste, use apenas o stub offline.
- `message-register.sh` é o contrário: grava no contexto da conversa e **não**
  entrega nada ao cliente.

### Exportação em arquivo

`GET /conversations/{id}/export` devolve **binário** (planilha xlsx; 8 KB numa
conversa de teste). Como o helper HTTP da lib só lida com JSON em memória, o
`export-conversation.sh` é o único script desta skill que usa `curl -o`
diretamente. Sem `--out`, o nome do arquivo é `<conversation-id>.<ext>`, com a
extensão derivada do `Content-Type` (`.xlsx`, `.csv`, `.json`, `.zip`, `.txt`).
Com `CV_JSON=1` a saída em stdout é `{"out","bytes","contentType"}`.

### Limites e erros

Rate limit **60 req/min** e **10.000 req/dia** (payload máx. 1 MB). O helper HTTP
reprocessa `429` com backoff. Códigos tratados: `400`, `401`, `403`, `402`
(quota do plano), `404`, `406` (sessão de canal expirada, ex. WhatsApp após 24 h),
`5xx`. Exit codes: `0` ok · `1` erro de cliente · `3` quota (402) · `4` rede ·
`5` servidor · `130` cancelado.

## Scripts auxiliares

- `scripts/assign.sh [api-key] <conversation-id> (--email <e> | --id <user-id> | --membership-id <id>) [--force] [--yes]`
  — atribui a conversa a um atendente (`--force` sobrescreve atribuição atual,
  que sem ele responde 409).
- `scripts/unassign.sh [api-key] <conversation-id> [--yes]` — remove o atendente.
- `scripts/set-status.sh [api-key] <conversation-id> <RESOLVED|UNRESOLVED|HUMAN_REQUESTED> [--yes]`
  — status (aceita minúsculas; valor inválido sai com exit 1 sem chamar a API).
- `scripts/set-priority.sh [api-key] <conversation-id> <LOW|MEDIUM|HIGH> [--yes]`
  — prioridade.
- `scripts/set-ai-enabled.sh [api-key] <conversation-id> <on|off> [--yes]`
  — liga/desliga a IA da conversa.
- `scripts/notes.sh [api-key] <conversation-id> --action <list|create|update|delete> [--note "<texto>"] [--note-id <id>] [--private|--public] [--justify] [--notification-datetime <ISO>] [--yes]`
  — CRUD das notas internas da conversa.
- `scripts/tags.sh [api-key] <conversation-id> <list|add> [--tag <nome>] [--yes]`
  — etiquetas de conversa; explica o 401 (a API key não é aceita nesse endpoint).
- `scripts/variables.sh [api-key] <conversation-id> <list|get|set|delete> [--name <varName>] [--value "<valor>"] [--yes]`
  — variáveis de contexto da conversa (valida os limites de tamanho localmente).
- `scripts/message-register.sh [api-key] <conversation-id> --message "<texto>" [--from human|agent]`
  — registra um evento no contexto **sem enviar** ao cliente.
- `scripts/send-message.sh [api-key] (--conversation-id <id> | --phone <n> | --email <e>) --message "<texto>" [--agent-id <id>] [--channel <website|dashboard|whatsapp|zapi|telegram|instagramDm>] [--visitor-id] [--contact-id] [--attachment-url <url> [--attachment-name] [--attachment-mime]] --yes`
  — **ENVIO REAL** ao cliente; `--yes` obrigatório.
- `scripts/send-audio.sh [api-key] <conversation-id> --audio-url <url> [--duration <segundos>] --yes`
  — **ENVIO REAL** de áudio ao cliente; `--yes` obrigatório.
- `scripts/export-conversation.sh [api-key] <conversation-id> [--out <arquivo>]`
  — baixa a exportação binária da conversa.
- `scripts/history.sh [api-key] --email <e-mail> --agent-id <id> [--limit N] [--cursor <token>]`
  — histórico de conversas da organização (filtros obrigatórios).

Saída: resultados em **stdout**, diagnósticos e avisos em **stderr**. Com
`CV_JSON=1` o stdout contém **somente JSON**.
