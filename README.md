# Chatvolt Skills

Conjunto de skills para o **pi** (agente de IA) que permitem gerenciar, testar e ajustar agentes Chatvolt via API.

## Skills incluídas

| Skill | Descrição |
|-------|-----------|
| `chatvolt-investigation` | Investiga agentes: busca configuração, lista conversas, recupera mensagens e analisa conformidade |
| `chatvolt-prompt-adjust` | Ajusta prompts, modelo e temperatura de agentes |
| `chatvolt-tools-update` | Gerencia ferramentas (tools) dos agentes: datastore, HTTP e form |
| `chatvolt-agent-test` | Testa agentes enviando queries e verificando se seguem o system prompt |

## Localização das skills

As skills originais estão em `~/.pi/agent/skills/` e são automaticamente detectadas pelo pi.

Este repositório contém links simbólicos para facilitar o acesso e consulta.

## Pré-requisitos

- **pi** (agente de IA) instalado
- Chave de API do Chatvolt: https://app.chatvolt.ai/settings/api-keys

## Como usar

### Pelo pi (recomendado)

O pi carrega as skills automaticamente quando o contexto for compatível.
Você também pode forçar o carregamento com:

```
/skill:chatvolt-investigation
/skill:chatvolt-prompt-adjust
/skill:chatvolt-tools-update
/skill:chatvolt-agent-test
```

### Direto pelo terminal

Cada skill tem scripts na pasta `scripts/` que podem ser executados diretamente:

```bash
# Ver configuração de um agente
~/.pi/agent/skills/chatvolt-agent-test/scripts/get-agent.sh "sk-..." "agent-id"

# Testar agente interativamente
~/.pi/agent/skills/chatvolt-agent-test/scripts/test-agent.sh "sk-..." "agent-id"

# Listar tools de um agente
~/.pi/agent/skills/chatvolt-tools-update/scripts/list-tools.sh "sk-..." "agent-id"
```

## Dica: variáveis de ambiente

Para não digitar a chave toda hora:

```bash
export CHATVOLT_API_KEY="sk-..."
export CHATVOLT_AGENT_ID="cminahdll02m496hey09nozu8"
```

## Visão geral da API Chatvolt

| Método | Endpoint | Skill |
|--------|----------|-------|
| `GET` | `/agents/{id}` | investigation, prompt-adjust, agent-test |
| `PATCH` | `/agents/{id}` | prompt-adjust |
| `POST` | `/agents/{id}/query` | investigation, agent-test |
| `GET` | `/api/agents/{id}/tools` | tools-update |
| `GET` | `/api/agents/{id}/tools/{toolId}` | tools-update |
| `POST` | `/api/agents/{id}/tools` | tools-update |
| `PATCH` | `/api/agents/{id}/tools/{toolId}` | tools-update |
| `DELETE` | `/api/agents/{id}/tools/{toolId}` | tools-update |
| `GET` | `/conversation?agentId={id}` | investigation |
| `GET` | `/conversation/{id}/messages/{count}` | investigation |

Base URL: `https://api.chatvolt.ai`
Autenticação: `Authorization: Bearer <api-key>`
