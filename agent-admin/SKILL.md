---
name: chatvolt-agent-admin
description: >
  Administra agentes do Chatvolt pela API: lista e cria agentes (com
  name+description+systemPrompt), deleta agentes, gerencia a whitelist de
  WhatsApp e a blacklist de usuários e envia formulários a um agente. Use para
  criar ou apagar um agente, liberar números no WhatsApp, bloquear usuários ou
  disparar um formulário para o agente responder.
---

# Chatvolt Agent Admin

Você me diz o que quer administrar — um agente (criar, listar, apagar), a
whitelist de WhatsApp, a blacklist de usuários ou o envio de um formulário — e
eu opero a API do Chatvolt com validação, confirmação e mensagens de erro
específicas. A cota de agentes é por plano: criar pode responder `402
USAGE_LIMIT`, tratado com aviso claro.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys)
> e, para whitelist/blacklist, o `agentId` do agente.

## Como funciona

1. Você informa a **API key** (1º argumento ou `CHATVOLT_API_KEY`).
2. **Listar agentes** com `list-agents.sh` (filtro por nome/id/handle).
3. **Criar** um agente com `create-agent.sh` — a API exige `name`,
   `description` e `systemPrompt`; a criação pede confirmação.
4. **Apagar** um agente com `delete-agent.sh` — lê o agente antes (para você ver
   o que será apagado), avisa que os dados associados também são removidos e
   pede confirmação.
5. **Whitelist/blacklist** com subcomandos `list | add | remove` (e `update` na
   whitelist); remoções pedem confirmação.
6. **Enviar formulário** a um agente com `submit-form.sh` (pede confirmação,
   pois a resposta vai para uma conversa real).

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents` | Lista os agentes da organização (array na raiz) |
| `POST` | `/agents` | Cria um agente (exige `name` + `description` + `systemPrompt`) |
| `GET` | `/agents/{id}` | Detalhe de um agente (usado antes do delete) |
| `DELETE` | `/agents/{id}` | Remove o agente e seus dados associados |
| `GET` | `/agent-whitelist-whatsapp/{id}` | Lista os números liberados do agente |
| `POST` | `/agent-whitelist-whatsapp` | Adiciona número(s) (`agentId` + `whatsappNumber`) |
| `PATCH` | `/agent-whitelist-whatsapp/{id}` | Troca um número (`oldWhatsappNumber` → `newWhatsappNumber`) |
| `DELETE` | `/agent-whitelist-whatsapp/{id}` | Remove um número (`whatsappNumber` no corpo) |
| `GET` | `/agent-blacklist` | Lista a blacklist da organização (404 neste ambiente) |
| `GET` | `/agent-blacklist/{agentId}` | Lista a blacklist de um agente (404 neste ambiente) |
| `POST` | `/agent-blacklist` | Adiciona usuário(s) (`agentId` + `userIdentify`) |
| `DELETE` | `/agent-blacklist/{agentId}?id=<entry-id>` | Remove uma entrada |
| `POST` | `/forms/{formId}/chat` | Envia um formulário ao agente (`{form:{fields:[{label,value}]}}`) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/agents/reference>

### Contratos e limites

- **`GET /agents`** devolve um **array na raiz** (sem envelope `{data:...}`).
  `GET /agents/{id}` aceita o id ou o handle (`@meu-agente`).
- **`POST /agents`** — a doc diz que só `name` é obrigatório, mas a API real
  exige também `description` e `systemPrompt` (só `name` → `400 invalid request
  body`). Campos aceitos: `modelName`, `temperature` (0.0–1.0), `visibility`
  (`public`/`private`), `handle`, `tools`, `interfaceConfig`, etc. Envie um
  campo extra com `--json '<objeto>'`.
- **Cota de agentes (`402 USAGE_LIMIT`)** — o número de agentes é limitado pelo
  plano. Verificado ao vivo em 2026-10-12: `POST /agents` com corpo válido
  responde `402 {"error":"USAGE_LIMIT"}` nesta organização. O
  `create-agent.sh` detecta esse caso e explica como liberar (apagar um agente
  ou fazer upgrade) em vez de falhar com erro genérico.
- **`DELETE /agents/{id}`** remove **também** os dados associados (service
  providers, permissões). Por isso o script confirma antes.
- **Whitelist de WhatsApp** — o corpo identifica o agente por `agentId` e aceita
  um número (string) ou vários (array). `POST` responde `409` se o número já
  estiver na whitelist. Um `404` costuma indicar agente inexistente.
- **Blacklist** — `userIdentify` aceita e-mail, telefone, IP, etc. A remoção usa
  `?id=<entry-id>` (o `agentId` vai no path, mas não é usado na lógica de
  exclusão). **Disponibilidade: TODAS as rotas `/agent-blacklist*` responderam
  HTTP 404 neste ambiente (2026-10-12)** — a doc lista, mas o plano/organização
  não expõe o recurso. Os scripts avisam isso explicitamente em vez de “erro
  genérico”; o caminho feliz é validado no stub de teste.
- **`POST /forms/{formId}/chat`** responde `{data:{...},success:true}` — é uma
  escrita que envia dados a um agente real, então `submit-form.sh` confirma.
- Erros tratados: `400`, `401/403` (chave/permissão), `402` (quota, exit 3),
  `404`, `406`, `429` (backoff automático), `5xx`. Rate limit: 60 req/min,
  10.000 req/dia, payload 1 MB.

## Scripts auxiliares

- `scripts/list-agents.sh [api-key] [--filter <regex>] [--limit <n>]`
  — lista os agentes (id, nome, modelo, visibilidade, handle); `--filter` casa
  nome/id/handle (case-insensitive).
- `scripts/create-agent.sh [api-key] --name <n> --description <d> --system-prompt <p> [--model <m>] [--temperature <t>] [--visibility public|private] [--handle <slug>] [--json '<extra>'] [--yes]`
  — cria um agente (valida os três campos obrigatórios, monta o JSON com
  `python3`, confirma e trata `402 USAGE_LIMIT`).
- `scripts/delete-agent.sh [api-key] <agent-id> [--yes]`
  — lê o agente, mostra o que será apagado, avisa sobre os dados associados,
  confirma e executa o `DELETE`.
- `scripts/whitelist.sh [api-key] <list|add|update|remove> ... [--yes]`
  — `list <agent-id>` · `add <agent-id> <num> [<num>…]` ·
  `update <agent-id> <antigo> <novo>` · `remove <agent-id> <num>` (confirma).
- `scripts/blacklist.sh [api-key] <list|add|remove> ... [--yes]`
  — `list [agent-id]` · `add <agent-id> <ident> [<ident>…]` ·
  `remove <agent-id> <entry-id>` (confirma). Explica o `404` do ambiente.
- `scripts/submit-form.sh [api-key] <form-id> --field "Rótulo=Valor" [--field …] [--json '<extra>'] [--yes]`
  — envia o formulário ao agente (confirma).

Saída: resultados em **stdout**, diagnósticos em **stderr**. Com `CV_JSON=1` o
stdout contém **somente JSON**. Exit codes: `0` ok · `1` erro de cliente ·
`3` quota (402) · `4` rede · `5` servidor · `130` cancelado.
