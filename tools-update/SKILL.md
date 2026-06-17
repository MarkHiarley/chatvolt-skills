---
name: chatvolt-tools-update
description: >
  Gerencia as ferramentas (tools) de agentes Chatvolt via API. Permite
  listar, criar, visualizar, atualizar e deletar tools dos tipos datastore,
  HTTP e form. Use quando precisar adicionar uma nova integração, ajustar
  a configuração de uma ferramenta existente, ou remover ferramentas de um agente.
---

# Chatvolt Tools Management

Gerencia as ferramentas (tools) de agentes Chatvolt. Você me diz **o que quer fazer** com as tools do agente.

> **Pré-requisitos:** Chave de API do Chatvolt (https://app.chatvolt.ai/settings/api-keys)

## Como funciona

1. Você informa a **API key** e o **ID do agente**
2. Me diz o que quer fazer:
   - **Listar** tools — mostro todas as ferramentas configuradas
   - **Ver detalhes** de uma tool — mostro a configuração completa
   - **Criar** uma nova tool — você define o tipo e a configuração
   - **Atualizar** uma tool existente — você passa os novos parâmetros
   - **Deletar** uma tool — removo do agente

## Tipos de tool

### Datastore
Conecta o agente a uma base de conhecimento.

| Campo | Obrigatório |
|-------|-------------|
| `type: "datastore"` | Sim |
| `datastoreId` | Sim |

### HTTP
Faz requisições para APIs externas.

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `type: "http"` | Sim | |
| `isRaw` | Não | Se true, usa raw cURL |
| `config.name` | Sim | Nome único e descritivo |
| `config.description` | Sim | Descrição para o agente decidir quando usar |
| `config.url` | Sim | URL (suporta `:variavel` para path variables) |
| `config.method` | Sim | GET, POST, PUT, DELETE, PATCH |
| `config.withApproval` | Não | Requer aprovação do usuário |
| `config.headers` | Não | Array de `{key, value, isUserProvided, description, acceptedValues}` |
| `config.body` | Não | Key-value para urlencoded/form-data |
| `config.rawBody` | Não | JSON bruto (mutuamente exclusivo com body) |
| `config.queryParameters` | Não | Parâmetros de URL |
| `config.pathVariables` | Não | Variáveis de path |

### Form
Conecta o agente a um formulário.

| Campo | Obrigatório |
|-------|-------------|
| `type: "form"` | Sim |
| `formId` | Sim |

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/api/agents/{agentId}/tools` | Listar tools |
| `GET` | `/api/agents/{agentId}/tools/{toolId}` | Detalhes de uma tool |
| `POST` | `/api/agents/{agentId}/tools` | Criar tool |
| `PATCH` | `/api/agents/{agentId}/tools/{toolId}` | Atualizar tool |
| `DELETE` | `/api/agents/{agentId}/tools/{toolId}` | Deletar tool |

Base URL: `https://api.chatvolt.ai`
Autenticação: `Authorization: Bearer <api-key>`

## Scripts auxiliares

Na pasta `scripts/` tem utilitários que posso usar quando necessário:

- `list-tools.sh <api-key> <agent-id>` — lista tools em tabela
- `get-tool.sh <api-key> <agent-id> <tool-id>` — detalhes de uma tool
- `create-tool.sh <api-key> <agent-id> <tipo> <config>` — cria tool (datastore, http, form)
- `update-tool.sh <api-key> <agent-id> <tool-id> <json>` — atualiza tool
- `delete-tool.sh <api-key> <agent-id> <tool-id>` — deleta tool (com confirmação)
- `manage-tools.sh <api-key> <agent-id>` — menu interativo
