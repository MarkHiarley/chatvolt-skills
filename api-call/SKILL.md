---
name: chatvolt-api-call
description: >
  Chama qualquer endpoint da API pública do Chatvolt com tratamento de erro,
  paginação e streaming, e mantém o índice completo das rotas disponíveis. Use
  quando precisar de uma rota que nenhuma outra skill cobre, para descobrir o
  que a API oferece, ou para reproduzir uma requisição exata.
---

# Chatvolt API — chamada genérica e catálogo

Cobre **todas** as rotas da API pública do Chatvolt (136 operações em 23 grupos,
extraídas do `openapi.yaml` publicado) sem depender de uma skill específica.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys).
> Algumas rotas exigem IDs específicos (agente, base, conversa, cenário).

## Como funciona

1. Você me diz o que quer fazer (ou qual endpoint).
2. Se a rota tem skill dedicada, eu uso a skill (contrato mais seguro); se não tem, uso `call.sh`.
3. Para descobrir a rota certa, consulto o catálogo com `catalog.sh`.

## API usada

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>`
Documentação: <https://chat-volt.mintlify.app/pages/agents/reference> · índice <https://chat-volt.mintlify.site/llms.txt>
Catálogo local (fonte): `data/endpoints.json` — gerado de <https://chat-volt.mintlify.app/openapi.yaml>.

### Grupos cobertos (136 operações)

| Grupo | O que cobre |
|---|---|
| `agents` | agentes, tools, models, query, webhook |
| `conversation` / `conversations` | listagem, mensagens, notas, tags, variáveis, export, assign/status/prioridade/IA |
| `contacts` | contatos e variáveis de contato |
| `datastores` / `datasources` | bases de conhecimento, fontes e busca semântica |
| `crm` | cenários, etapas, logs de conversa, eventos (SSE) |
| `dispatches` | disparos, listas e contatos de disparo |
| `artifacts` / `artifact-categories` | catálogo de artefatos, categorias e mídia |
| `whatsapp` / `messages` | templates, mensagens interativas e envio por template |
| `twilio` / `zapi` / `zapper` | envio via integrações de WhatsApp |
| `mercadolivre` | produtos sincronizados do Mercado Livre |
| `tags`, `variables`, `forms`, `agent-whitelist-whatsapp`, `webhook`, `agent-blacklist`, `agent-templates` | rotas auxiliares — algumas ausentes no ambiente atual |

### Disponibilidade medida ao vivo (2026-10-12)

- **Ausentes neste plano/organização (HTTP 404):** `/agent-blacklist`, `/agent-blacklist/{agentId}`, `/agent-templates/{organizationId}`, `/conversations/export`, `/whatsapp/conversion-tracking`, `/tags`, `/tags/delete-by-name`, `/tags/get-visible-tags`, `/webhook/validate`.
- **Exige sessão do dashboard (401 com API key):** `GET/POST /conversations/{id}/tags`.
- **Streaming:** `GET /crm/events` responde `text/event-stream` (evento inicial `CONNECTED`) — use `--stream` e `--max-time`.
- **Binário:** `GET /conversations/{id}/export` devolve arquivo (zip/csv) — use `--out`.
- **Público (sem auth):** `GET /agents/models`.

## Scripts auxiliares

- `catalog.sh [--group <g>] [--filter <regex>] [--available-only] [--list-groups]`
  — índice das 136 operações com método, caminho e disponibilidade.
- `call.sh <api-key> <MÉTODO> <caminho> [--json … | --data-file … | --form k=v] [--query k=v]… [--raw] [--no-unwrap] [--stream] [--out <arquivo>] [--all] [--max-time <s>]`
  — chamada genérica: desembrulha `{data}` quando existir, trata 401/402/403/404/406/429/5xx, pagina com `--all` (respostas com `pagination.offset/limit`) e salva binários com `--out`.

## Exemplos

```bash
./api-call/scripts/catalog.sh --group crm
./api-call/scripts/catalog.sh --filter 'artifacts|artifact-categories'
./api-call/scripts/call.sh "$CHATVOLT_API_KEY" GET /conversation --query agentId="$CHATVOLT_AGENT_ID" --query limit=5
./api-call/scripts/call.sh "$CHATVOLT_API_KEY" POST /agents/"$CHATVOLT_AGENT_ID"/query --json '{"query":"Bom dia"}'
./api-call/scripts/call.sh "$CHATVOLT_API_KEY" GET /crm/events --query scenarioId="$SC" --stream --max-time 30
./api-call/scripts/call.sh "$CHATVOLT_API_KEY" GET /conversations/"$CONV"/export --out conversa.zip
```

Sempre que existir skill dedicada (`chatvolt-contacts`, `chatvolt-crm`, `chatvolt-dispatches`, …),
prefira-a: o contrato ali é validado com teste; aqui é a rota crua.
