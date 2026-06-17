---
name: chatvolt-prompt-adjust
description: >
  Ajusta prompts e configurações de agentes Chatvolt via API. Permite
  ler o system prompt atual, editá-lo, alterar modelo, temperatura,
  e testar o comportamento. Use quando precisar diagnosticar e corrigir
  problemas de comportamento de um agente, otimizar seu system prompt,
  ou ajustar parâmetros como modelo e temperatura.
---

# Chatvolt Prompt Adjustment

Ajusta agentes Chatvolt. Você me diz **o que quer mudar** — prompt, modelo ou temperatura — e eu aplico as alterações.

> **Pré-requisitos:** Chave de API do Chatvolt (https://app.chatvolt.ai/settings/api-keys)

## Como funciona

1. Você informa a **API key** e o **ID do agente**
2. Me diz o que quer fazer:
   - **Ver configuração atual** — mostro o system prompt, modelo, temperatura e tools
   - **Editar o system prompt** — você me passa o novo prompt (ou ajustes no atual)
   - **Trocar o modelo** — você escolhe o modelo (GPT, Gemini, Claude, DeepSeek, etc.)
   - **Ajustar temperatura** — você define o valor (0.0 a 1.0)
   - **Testar o comportamento** — envio uma query e mostro a resposta

## Exemplos de modelos disponíveis

`gpt_4_o`, `gpt_41`, `gpt_41_mini`, `gpt_o3_mini`, `gpt_o4_mini`, `gemini_flash`, `gemini_pro`, `claude_3_haiku`, `claude_3_sonnet`, `claude_sonnet`, `deepseek_v3`, `deepseek_r1`, `sabia_3`, `llama_4_scout`, `llama_4_maverick`, `grok_3`, `grok_3_mini`, `qwen_max`, `mistral_large`, `command_a` e outros.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents/{id}` | Obter detalhes do agente |
| `PATCH` | `/agents/{id}` | Atualizar configuração do agente |
| `POST` | `/agents/{id}/query` | Enviar query de teste |
| `GET` | `/agents/{id}/tools` | Listar ferramentas do agente |

Base URL: `https://api.chatvolt.ai`
Autenticação: `Authorization: Bearer <api-key>`

### Campos que podem ser alterados via PATCH

- `systemPrompt` — novo prompt
- `modelName` — novo modelo
- `temperature` — nova temperatura (0.0–1.0)
- `name`, `description`, `visibility`, `handle` — metadados do agente
- `interfaceConfig` — configurações de interface
- `enableInactiveHours`, `inactiveHours` — horário de inatividade

## Scripts auxiliares

Na pasta `scripts/` tem utilitários que posso usar quando necessário:

- `get-agent.sh <api-key> <agent-id>` — mostra configuração atual
- `update-prompt.sh <api-key> <agent-id> "<prompt>"` — atualiza prompt
- `update-model.sh <api-key> <agent-id> <modelo>` — troca modelo
- `update-temperature.sh <api-key> <agent-id> <valor>` — ajusta temperatura
- `test-query.sh <api-key> <agent-id> <query> [temp] [modelo]` — testa
- `adjust.sh <api-key> <agent-id> <query>` — fluxo interativo
