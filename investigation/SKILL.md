---
name: chatvolt-investigation
description: >
  Investiga agentes Chatvolt: busca configuração (system prompt, modelo,
  temperatura, ferramentas), lista conversas e recupera mensagens. Use
  quando precisar auditar o comportamento de um agente ou analisar
  conversas existentes.
---

# Chatvolt Agent Investigation

Investiga agentes Chatvolt. Você me diz **o que quer investigar** — configuração do agente, conversas recentes, mensagens específicas — e eu busco as informações.

> **Pré-requisitos:** Chave de API do Chatvolt (https://app.chatvolt.ai/settings/api-keys)

## Como funciona

1. Você informa a **API key** e o **ID do agente** (UUID ou handle com `@`)
2. Me diz o que quer investigar:
   - **Configuração do agente** — system prompt, modelo, temperatura, tools
   - **Conversas recentes** — lista com opção de filtro por data/status
   - **Mensagens de uma conversa** — histórico completo
   - **Análise de conformidade** — verificar se o agente segue o prompt

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents/{id}` | Detalhes do agente |
| `GET` | `/conversation?agentId={id}&createdAt={data}` | Listar conversas por data |
| `GET` | `/conversation/{id}/messages/{count}` | Mensagens de uma conversa |
| `POST` | `/agents/{id}/query` | Enviar query de teste |

Base URL: `https://api.chatvolt.ai`
Autenticação: `Authorization: Bearer <api-key>`

## Scripts auxiliares

Na pasta `scripts/` tem utilitários que posso usar quando necessário:

- `agent.sh <api-key> <agent-id>` — detalhes do agente em JSON
- `list-conversations.sh <api-key> <agent-id> [dias] [limite] [status]` — lista conversas
- `get-messages.sh <api-key> <conversation-id> [quantidade]` — mensagens da conversa
- `test-query.sh <api-key> <agent-id> <query>` — testar comportamento
- `investigate.sh <api-key> <agent-id> [dias] [limite]` — investigação completa
