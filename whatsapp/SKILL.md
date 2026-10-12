---
name: chatvolt-whatsapp
description: >
  Lista e cria templates da WABA e envia mensagens de WhatsApp pelo Chatvolt
  (template aprovado e mensagens interativas: botões, listas, CTA, localização,
  contato, pedido de localização). Use para operar o canal oficial de WhatsApp
  de um agente, conferir quais templates estão aprovados antes de enviar, ou
  montar o payload correto das rotas /messages/interactive/*.
---

# Chatvolt WhatsApp

Você me diz o agente, a conversa e o que deve ser enviado (ou qual template
você procura), e eu monto a requisição conforme o contrato do WhatsApp oficial
do Chatvolt: listo/crio templates da WABA e envio mensagens de template ou
interativas. Todo envio exige `--yes` explícito e imprime um aviso de que a
mensagem é real.

> **Pré-requisitos:** chave de API
> (https://app.chatvolt.ai/settings/api-keys), um `agentId` com WhatsApp
> configurado, o `conversationId` da conversa (para as mensagens interativas) e
> o `phoneNumberId` (para envio de template).

## Regras críticas

1. **Todo envio é real.** As rotas `/messages/interactive/*` e
   `/whatsapp/{phoneNumberId}/template-message` entregam mensagem no WhatsApp do
   cliente. Todos os scripts exigem `--yes` (ou `CV_YES=1`) e emitem o aviso em
   stderr antes de chamar a API.
2. **Nunca dispare envio em teste ao vivo.** Essas rotas são validadas apenas
   nas fixtures do stub local (`tests/stub-fixtures/whatsapp.json`).
3. **Primeira mensagem tem que ser template aprovado.** Mensagens livres e
   interativas só valem depois que o contato responde.
4. **Template criado vai para aprovação da Meta** (`status: pending`) e **não
   existe rota de exclusão** — criar é irreversível pela API, por isso o
   subcomando `create` pede confirmação (pulável com `--yes`).
5. **Limites do contrato:** até 3 botões; `button_text` ≤ 20 caracteres;
   `header_text`/`footer_text` ≤ 60; `body_text` ≤ 4096.
6. **`agentId` é obrigatório em tudo.** Em `GET /whatsapp/templates` ele vai na
   query; agente sem WhatsApp configurado responde `400 Agent does not have
   WhatsApp configured`.

## Como funciona

1. Você informa a **API key** (1º argumento ou `CHATVOLT_API_KEY`).
2. **Descobrir o template:** `templates.sh list --agent <id>` mostra nome,
   idioma, status e categoria; filtre com `--status approved` para ver só o que
   pode ser enviado.
3. **Enviar template:** `send-template.sh` monta `to`, `text`, `agentId`,
   `templateName` e `templateLangCode` (+ `var_*` e `buttons` opcionais).
4. **Mensagem interativa:** `send-buttons.sh`, `send-lists.sh`, `send-cta.sh`,
   `send-location.sh`, `send-contact.sh` e `location-request.sh` — todas exigem
   `--conversation` (o envio acontece na conversa, não em um `to` livre).
5. **Criar template:** `templates.sh create` com `--body` (ou `--components`
   JSON cru para variáveis/exemplos).

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/whatsapp/templates?agentId=` | Lista os templates da WABA do agente |
| `POST` | `/whatsapp/templates` | Cria template (envia para aprovação da Meta) |
| `POST` | `/whatsapp/{phoneNumberId}/template-message` | Envia template aprovado (**envio real**) |
| `POST` | `/messages/interactive/send-buttons` | Até 3 botões de resposta (**envio real**) |
| `POST` | `/messages/interactive/send-lists` | Menu com lista de opções (**envio real**) |
| `POST` | `/messages/interactive/send-cta` | Botão de URL / CTA (**envio real**) |
| `POST` | `/messages/interactive/send-location` | Envia um pin de localização (**envio real**) |
| `POST` | `/messages/interactive/send-contact` | Envia cartão de contato (**envio real**) |
| `POST` | `/messages/interactive/location-request` | Pede a localização do contato (**envio real**) |
| `GET` | `/whatsapp/conversion-tracking` | Tracking de conversão — **404 neste ambiente** |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/whatsapp/reference>

### Contrato das rotas de envio (`openapi.yaml`)

| Rota | Campos obrigatórios | Opcionais |
|------|---------------------|-----------|
| `send-buttons` | `agentId`, `conversationId`, `body_text`, `button_1_id`, `button_1_title` | `header_text`, `footer_text`, `button_2_*`, `button_3_*` |
| `send-lists` | `agentId`, `conversationId`, `body_text`, `button_text` | `header_text` (≤60), `footer_text` (≤60), `list_title` |
| `send-cta` | `agentId`, `conversationId`, `body_text`, `button_display_text`, `button_url` (http/https) | `header_text`, `footer_text` |
| `send-location` | `agentId`, `conversationId`, `latitude`, `longitude`, `name`, `address` | — |
| `send-contact` | `agentId`, `conversationId`, `name_formatted_name` | `additionalProperties: true` (aceita extras; `--json`) |
| `location-request` | `agentId`, `conversationId`, `body_text` | `header_text` |
| `template-message` | `to`, `text`, `agentId`, `templateName`, `templateLangCode` | `defaultStatus`, `buttons[]`, `var_*` |
| `POST /whatsapp/templates` | `agentId`, `name`, `category`, `language`, `components` | — |

Detalhes que o contrato exige e os scripts validam:

- `latitude`/`longitude` são **strings decimais** (ex.: `"-23.5505"`), não números.
- `buttons[]` do template: `type` ∈ `url`, `quick_reply`, `copy_code`, `flow`,
  `catalog`, mais `value` e `index`.
- Variáveis dinâmicas do template usam o prefixo **`var_`**
  (`^var_[a-zA-Z_][a-zA-Z0-9_]*$`), ex.: `var_customer_name`; no `text` as
  variáveis são posicionais (`{{1}}`, `{{2}}`).
- `category` do template: `MARKETING`, `UTILITY` ou `AUTHENTICATION`; `name` só
  aceita minúsculas, números e `_`.
- O campo de idioma do envio é **`templateLangCode`** (não `language`).
- As mensagens interativas usam **snake_case** (`body_text`, `button_text`,
  `name_formatted_name`). Os exemplos de visão geral da doc (`to`, `name`,
  `language`, `components` em `send-contact`) divergem do contrato — vale o
  `openapi.yaml`.

### Disponibilidade e formato medidos ao vivo (2026-10-12)

- `GET /whatsapp/templates?agentId=<id>` → `200` com
  `{"data":[{"id","name","language","status","category","components"}]}`.
  O **status vem em maiúsculas** (`APPROVED`, `REJECTED`, `PENDING`) e o
  `components` traz os blocos da Meta (`BODY`, `BUTTONS`, ...).
- Sem `agentId`: `400 {"error":"Invalid request body (validation failed)",
  "details":{"agentId":{"_errors":["Required"]}}}`.
- Agente sem WhatsApp configurado: `400 {"error":"Agent does not have WhatsApp
  configured"}`.
- `GET /whatsapp/conversion-tracking` → **404** neste ambiente (corpo texto
  `not found`, não JSON).
- `create`/envios **não foram disparados ao vivo** (envio real e template sem
  exclusão); o caminho feliz é provado pelas fixtures do stub, com os nomes de
  campo conferidos contra o `openapi.yaml`.

## Scripts auxiliares

- `templates.sh [api-key] list --agent <id> [--status <approved|rejected|pending>]`
  — lista os templates da WABA (o contrato exige `agentId`); `--status` filtra
  localmente (comparação sem diferenciar maiúsculas).
- `templates.sh [api-key] create --agent <id> --name <n> --category <c> --language <l> (--body <texto> | --components '<json>') [--header <t>] [--footer <t>] [--yes]`
  — cria o template na WABA e o envia para aprovação da Meta (pede confirmação).
- `send-template.sh [api-key] --phone-number <id> --to <numero> --text <t> --template <nome> --lang <codigo> [--agent <id>] [--default-status <s>] [--button <tipo>:<valor>:<index>]... [--var var_x=valor]... --yes`
  — envia template aprovado (**envio real**).
- `send-buttons.sh [api-key] --conversation <id> --body <t> --button <id>=<titulo>... [--agent <id>] [--header <t>] [--footer <t>] --yes`
  — mensagem com até 3 botões (**envio real**).
- `send-lists.sh [api-key] --conversation <id> --body <t> --button-text <t> [--list-title <t>] [--json '<extra>'] --yes`
  — menu com lista de opções (**envio real**).
- `send-cta.sh [api-key] --conversation <id> --body <t> --button-text <t> --url <https://...> --yes`
  — botão de URL (**envio real**).
- `send-location.sh [api-key] --conversation <id> --latitude <dec> --longitude <dec> --name <local> --address <endereço> --yes`
  — pin de localização (**envio real**).
- `send-contact.sh [api-key] --conversation <id> --name <nome> [--json '<extra>'] --yes`
  — cartão de contato (**envio real**).
- `location-request.sh [api-key] --conversation <id> --body <t> [--header <t>] --yes`
  — pede a localização do contato (**envio real**).

Saída: resultado em **stdout**, avisos/diagnósticos em **stderr**; com
`CV_JSON=1` o stdout contém **somente JSON**. Erros: `1` cliente, `3` quota
(402), `4` rede, `5` servidor, `130` cancelado. `429` é reprocessado com
backoff pelo helper HTTP (`CV_MAX_RETRIES`, `CV_RETRY_WAIT`).

## Exemplos

```bash
# Quais templates podem ser enviados agora?
./whatsapp/scripts/templates.sh "$CHATVOLT_API_KEY" list --agent "$CHATVOLT_AGENT_ID" --status approved

# Criar um template utilitário simples (após aprovação da Meta pode ser enviado)
./whatsapp/scripts/templates.sh "$CHATVOLT_API_KEY" create --agent "$CHATVOLT_AGENT_ID" \
  --name aviso_pedido --category UTILITY --language pt_BR \
  --body 'Olá {{1}}, seu pedido saiu para entrega.'

# Primeira mensagem: template aprovado com variável dinâmica
./whatsapp/scripts/send-template.sh "$CHATVOLT_API_KEY" --phone-number 123456789 \
  --to 55987654321 --agent "$CHATVOLT_AGENT_ID" --template boas_vindas --lang pt_BR \
  --text 'Olá {{1}}!' --var var_customer_name=João --yes

# Mensagem interativa dentro de uma conversa já iniciada
./whatsapp/scripts/send-buttons.sh "$CHATVOLT_API_KEY" --conversation "$CONV" \
  --agent "$CHATVOLT_AGENT_ID" --body 'Escolha uma opção:' --button sim=Sim --button nao=Não --yes

./whatsapp/scripts/send-cta.sh "$CHATVOLT_API_KEY" --conversation "$CONV" \
  --agent "$CHATVOLT_AGENT_ID" --body 'Acesse nosso site' --button-text 'Saiba mais' \
  --url https://chatvolt.ai --yes
```
