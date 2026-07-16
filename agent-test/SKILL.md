---
name: chatvolt-agent-test
description: >
  Testa agentes Chatvolt: envia queries, mantém conversa, e verifica se o
  comportamento segue as regras que você definir. Use quando precisar validar
  se um agente está seguindo corretamente suas instruções, testar cenários
  complexos, ou debuggar comportamento inesperado.
---

# Chatvolt Agent Testing

Testa agentes Chatvolt. Você me diz **o que quer testar** e **quais regras o agente deve seguir**, e eu conduzo o teste.

> **Pré-requisitos:** Chave de API do Chatvolt (https://app.chatvolt.ai/settings/api-keys)

## ⚠️ REGRA CRÍTICA: NUNCA ENVIAR EM CONVERSA EXISTENTE ⚠️

**NUNCA** envie queries em uma conversa existente (com `conversationId`) a menos que o usuário **explicitamente autorize e confirme**.

Motivo: Mensagens enviadas via API são **salvas permanentemente no histórico real da conversa** no Chatvolt. O cliente real pode ver essas mensagens. Isso polui o histórico e causa confusão.

**Sempre prefira criar uma nova conversa** (omitindo `conversationId`) para testes.

## Como funciona

1. Você informa a **API key** e o **ID do agente**
2. Me diz qual o **fluxo esperado** — as regras que o agente deve seguir (ex: "responder em português, se apresentar como suporte, nunca mencionar concorrentes")
3. **SEMPRE** inicie uma **nova conversa** para testes (não reutilize conversas reais)
4. Eu envio as perguntas que você definir, sempre na **mesma conversa de teste**
5. Quando você quiser, analiso se as respostas estão seguindo as regras

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents/{id}` | Obter detalhes do agente (prompt, modelo, tools) |
| `POST` | `/agents/{id}/query` | Enviar query e obter resposta |

Base URL: `https://api.chatvolt.ai`
Autenticação: `Authorization: Bearer <api-key>`

### Parâmetros da query

- `query` (obrigatório): texto da pergunta
- `conversationId`: ID de conversa existente. Se omitido/inválido, cria nova
- `temperature`: sobrescreve a temperatura do agente (0.0–1.0)
- `modelName`: sobrescreve o modelo do agente
- `contact`, `contactId`, `visitorId`: dados opcionais do contato

## Scripts auxiliares

Na pasta `scripts/` tem utilitários que posso usar quando necessário:

- `get-agent.sh <api-key> <agent-id>` — mostra configuração do agente
- `send-query.sh <api-key> <agent-id> <query> [conversation-id] [temp] [model]` — envia query
- `analyze-results.sh <api-key> <agent-id> <conv-id> <history-file> <fluxo>` — análise
- `test-agent.sh <api-key> <agent-id>` — modo interativo (se preferir)
