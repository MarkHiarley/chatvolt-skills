---
name: chatvolt-conversation-cleanup
description: >
  Gerencia conversas do Chatvolt: lista, busca e deleta conversas de teste
  via API. Use quando precisar limpar conversas de teste, encontrar uma
  conversa específica, ou deletar conversas criadas acidentalmente.
---

# Chatvolt Conversation Cleanup

Limpa conversas de teste no Chatvolt. Use quando sobrarem conversas de
teste (canal `api`) que poluem o dashboard.

> **Pré-requisitos:** Chave de API do Chatvolt (https://app.chatvolt.ai/settings/api-keys)

## ⚠️ REGRAS CRÍTICAS

1. **NUNCA** delete conversas de canais reais (`whatsapp`, `telegram`, `messenger`, `email`).
   Só delete conversas do canal `api` (criadas por testes).
2. **Sempre confirme** com o usuário antes de deletar qualquer conversa.
3. **NÃO** tem como deletar mensagens individuais — a API só permite deletar a
   conversa inteira.

## Como funciona

1. Você informa a **API key**
2. Pode:
   - **Listar conversas** — ver todas com filtro por canal/data
   - **Buscar conversa por ID** — ver detalhes de uma conversa
   - **Deletar conversas de teste** — apaga conversas do canal `api`

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/conversation?organizationId={id}&limit={n}` | Listar conversas |
| `DELETE` | `/conversation/{id}` | Deletar conversa |

Base URL: `https://api.chatvolt.ai`
Autenticação: `Authorization: Bearer <api-key>`

### Como obter o organizationId

O `organizationId` aparece na resposta de qualquer conversa. Dado um
conversationId, faça:

```
GET /conversation/{id}/messages/1
```

O campo `organizationId` vem no body da resposta.

## Scripts auxiliares

Na pasta `scripts/` tem utilitários:

- `list-conversations.sh <api-key> <org-id> [limite]` — lista conversas
- `delete-conversation.sh <api-key> <conv-id>` — deleta uma conversa
- `cleanup-test-conversations.sh <api-key> <org-id>` — deleta TODAS as
  conversas de canal `api` (pergunta antes)
