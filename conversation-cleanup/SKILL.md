---
name: chatvolt-conversation-cleanup
description: >
  Lista, inspeciona e remove conversas do Chatvolt pela API, com foco em
  apagar conversas de teste (canal api). Use para limpar conversas criadas
  por testes, encontrar uma conversa específica por agente/canal/data, ou
  deletar uma conversa com segurança.
---

# Chatvolt Conversation Cleanup

Você me diz qual agente, canal e período quer olhar (ou qual conversa quer
apagar), e eu listo, inspeciono e removo conversas usando a API. O foco é
limpar conversas de teste do canal `api` sem tocar em conversas reais.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys)
> e, opcionalmente, um `agentId`. A listagem funciona sem `agentId`, mas filtrar
> por agente deixa o resultado muito mais limpo.

## Regras críticas

1. **NUNCA** delete conversas de canais reais (`whatsapp`, `telegram`,
   `messenger`, `email`, `slack`). Só o canal `api` (conversas de teste) é
   seguro. O `delete-conversation.sh` recusa qualquer outro canal e exige
   `--force` para prosseguir.
2. **Sempre confirme** antes de deletar. `cleanup-test-conversations.sh` pede
   **duas** confirmações manuais (digitar `sim` duas vezes) antes de apagar em
   massa; `CV_YES=1` (ou `--yes`) pula as confirmações em automações.
3. **Não existe delete de mensagem individual** — a API só permite deletar a
   conversa inteira (`DELETE /conversation/{id}`).
4. `organizationId` **não é parâmetro** de `GET /conversation`. Ele só aparece
   como campo da resposta (objeto da conversa ou `GET /conversation/{id}/messages/1`).

## Como funciona

1. Você informa a **API key** (argumento ou `CHATVOLT_API_KEY`).
2. **Listar** conversas com filtros válidos: agente, canal, período, status.
   Use `--all` para paginar por cursor até o fim.
3. **Inspecionar** uma conversa específica (canal, status, contato) antes de
   qualquer exclusão.
4. **Deletar**: uma conversa (com checagem de canal) ou, em massa, todas as
   conversas de teste do canal `api` (com dupla confirmação).

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/conversation` | Lista conversas (array na raiz) com filtros |
| `GET` | `/conversation/{id}` | Objeto completo de uma conversa (inclui `channel`) |
| `GET` | `/conversation/{id}/messages/{n}` | Metadados + mensagens (`{status,isAiEnabled,userId,organizationId,messages[]}`) |
| `DELETE` | `/conversation/{id}` | Deleta a conversa → `{success,message,conversationId,channel}` |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/conversations/reference>

### Parâmetros de `GET /conversation`

| Parâmetro | Valores / observações |
|-----------|-----------------------|
| `agentId` | id do agente; aceita a string `null` |
| `channel` | `api`, `whatsapp`, `telegram`, `messenger`, `email`, `slack`, ... |
| `createdAt` | data inicial (`YYYY-MM-DD`); corresponde ao script `--days` / `--created-at` |
| `endDate` | data final (`YYYY-MM-DD`) |
| `status` | `RESOLVED` \| `UNRESOLVED` \| `HUMAN_REQUESTED` (valor inválido → `400 INVALID_REQUEST`) |
| `priority` | `LOW` \| `MEDIUM` \| `HIGH` |
| `assigneeId` | id do atendente ou `unassigned` |
| `unread`, `tag`, `ai` (`enabled`/`disabled`) | filtros adicionais |
| `limit` | itens por página; **padrão 25, máximo 100** |
| `cursor` | ver abaixo |

`organizationId` **não** é aceito aqui (é apenas campo da resposta).

### Paginação por cursor

O cursor é um **JSON cru url-encoded** com a posição do último item recebido:

```
cursor={"lastCreatedAt":"2026-10-10T19:03:30.173Z","lastId":"cmv2rijx90buivfpf2lc479h2"}
```

Um cursor inválido é ignorado pela API (devolve a primeira página). Por isso o
`--all` monta o cursor a partir do último item de cada página e para quando a
página vier com menos itens que o `limit`.

### Limites e erros

Rate limit **60 req/min** e **10.000 req/dia** (payload máx. 1 MB). Um `429` é
reprocessado com backoff pelo helper HTTP; no laço de exclusão em massa há ainda
uma pausa entre `DELETE`s (`CV_DELETE_PACE`, padrão 1s) para não estourar o
limite. Códigos tratados: `400`, `401`, `402` (quota), `403`, `404`, `406`, `429`,
`5xx`.

## Scripts auxiliares

- `scripts/list-conversations.sh [api-key] [--agent <id>] [--channel <c>] [--days N] [--created-at <d>] [--end-date <d>] [--status <s>] [--limit N] [--cursor <json>] [--all]`
  — lista conversas em tabela (id, canal, status, criação, contato, IA). `--all`
  pagina por cursor até o fim. Sem filtros válidos, sai erro de cliente.
- `scripts/delete-conversation.sh [api-key] <conv-id> [--force]`
  — busca a conversa (somente leitura), mostra canal/status/contato, **recusa se
  o canal não for `api`** (a menos de `--force`) e, após confirmação, executa o
  `DELETE`, imprimindo `{success,message}`.
- `scripts/cleanup-test-conversations.sh [api-key] [--agent <id>] [--days N] [--yes]`
  — lista **exaustivamente** (cursor) tudo com `channel == "api"`, mostra a
  contagem, pede dupla confirmação (ou `CV_YES=1`/`--yes`) e deleta
  sequencialmente com pausa/backoff, terminando com um resumo. Nunca toca em
  outros canais.

Saída: resultados em **stdout**, diagnósticos em **stderr**. Com `CV_JSON=1` o
stdout contém **somente JSON**.
