---
name: chatvolt-contacts
description: >
  Lista, cria, atualiza e remove contatos do Chatvolt e gerencia as variáveis
  customizadas de cada contato. Use para encontrar um cliente por e-mail,
  telefone ou nome, cadastrar/atualizar um contato, segmentar por tags/agente/
  status de conversa/cenário CRM, definir variáveis (ex.: plano, cargo) que o
  agente usa nas respostas, ou apagar um contato e suas variáveis.
---

# Chatvolt Contacts

Você me diz qual contato procura (e-mail, telefone, nome ou filtros como tag,
agente ou status de conversa) ou o que quer gravar nele, e eu listo, crio,
atualizo, removo contatos e gerencio as variáveis customizadas de cada um pela
API pública do Chatvolt.

> **Pré-requisitos:** Chave de API
> (https://app.chatvolt.ai/settings/api-keys) e, para operações de variáveis ou
> exclusão, o **id do contato** (obtido com `list-contacts.sh --search`).

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Como funciona

1. Você informa a **API key** (1º argumento ou `CHATVOLT_API_KEY`).
2. **Localizar** um contato: `list-contacts.sh --search <e-mail|telefone|nome>`
   (é o caminho mais rápido quando você não tem o id em mãos).
3. **Criar/atualizar**: `create-contact.sh` — sem `--id` cria; com `--id`
   atualiza o mesmo registro (`POST /contacts` faz upsert pelo id do corpo).
4. **Variáveis**: `list-contact-variables.sh`, `set-contact-variable.sh`
   (cria/atualiza) e `delete-contact-variable.sh` (uma chave ou todas).
5. **Remover**: `delete-contact.sh <contact-id>` — busca os dados antes, mostra
   o que será apagado e exige confirmação.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/contacts` | Lista contatos com filtros e paginação |
| `POST` | `/contacts` | Cria (sem `id`) ou atualiza (com `id`) um contato |
| `DELETE` | `/contacts/{id}` | Remove um contato |
| `GET` | `/contacts/variables?id=` | Lista as variáveis de um contato |
| `POST` | `/contacts/variables` | Cria/atualiza uma variável (upsert atômico) |
| `PUT` | `/contacts/variables` | Atualiza uma variável (equivalente ao POST) |
| `DELETE` | `/contacts/variables?id=[&key=]` | Remove uma variável (com `key`) ou todas (sem `key`) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/contacts/reference>

### `GET /contacts` — filtros

| Parâmetro | Valores / observações |
|-----------|-----------------------|
| `search` | e-mail, telefone, nome ou sobrenome |
| `tags` | lista de tags (o script envia uma ocorrência por `--tag`) |
| `agent` | id do agente |
| `conversationStatus` | `RESOLVED` \| `UNRESOLVED` \| `HUMAN_REQUESTED` |
| `priority` | `LOW` \| `MEDIUM` \| `HIGH` |
| `channel` | `website` \| `dashboard` \| `whatsapp` \| `zapi` \| `telegram` \| `instagramDm` |
| `crmScenario`, `crmStep` | ids do cenário/etapa do CRM |
| `startDate`, `endDate` | data ISO de criação (inclusiva) |
| `hasEmail`, `hasPhone` | booleanos (`true`/`false`) |
| `limit` | itens por página; **padrão pela API 100, máximo 100** |
| `offset` | declarado no `openapi.yaml`, mas **ignorado pela API** (verificado ao vivo em 2026-10-12: `offset=0/1/5` devolvem o mesmo item) |

**Resposta real (verificada ao vivo):**
`{"contacts":[{"id","email","phoneNumber","firstName","lastName","externalId","picture","metadata","organizationId","createdAt","updatedAt","latestConversationId","ctwaAttribution"}],"count":112,"hasMore":true,"nextCursor":"2026-10-06T14:40:11.518Z_cmuwsciym..."}`.
A paginação efetiva é pelo **`nextCursor`** devolvido (o `count` é o total da
organização). O `--all` dos scripts segue esse cursor até `hasMore=false`.

### `POST /contacts` — create/update

Corpo (`ContactPayload`): `id` (opcional — presente = update), `email`,
`phoneNumber`, `firstName`, `lastName`, `externalId`, `picture`, `metadata`.
Campos da doc narrativa como `name`/`phone` **não** existem no contrato real —
use `firstName`/`lastName` e `phoneNumber`. Telefone vai com DDI e sem `+`
(ex.: `5511988887777`); contatos são deduplicados por e-mail/telefone.

### `/contacts/variables`

- `id` aceita **id de contato ou id de conversa** (o primeiro contato
  participante é resolvido automaticamente). Sem `id` a API responde
  `400 {"error":"ID de contato é obrigatório"}` (verificado ao vivo).
- `POST`/`PUT` exigem `key`, `value` e `source` (`human` | `ai`); `value` aceita
  qualquer tipo JSON. O merge é atômico em JSONB (duas escritas em chaves
  diferentes não se sobrescrevem). Chaves iniciadas por `_` são reservadas.
- Resposta: `{"variables":{...}}` (o `GET` devolve também `variableList` com
  `{varName,varValue,source}`); a chave especial `_sources` mapeia cada variável
  para sua origem.
- `DELETE` sem `key` apaga o registro inteiro de variáveis do contato; com
  `key` devolve `404` se a chave não existir.

### Disponibilidade (medida ao vivo em 2026-10-12)

- `GET /contacts`, `POST /contacts`, `DELETE /contacts/{id}` e
  `/contacts/variables` (GET/POST/PUT/DELETE): **disponíveis**.
- **`GET /contacts/{id}` NÃO EXISTE** (elemento 404 `not found`): só há `DELETE`
  nesse path. Para inspecionar um contato, busque com
  `list-contacts.sh --search <termo>` e filtre pelo id.
- `GET /contacts/available-variables` **existe ao vivo** (`200`), mas não está no
  `openapi.yaml` publicado e não tem script nesta skill — use
  `api-call/scripts/call.sh <api-key> GET /contacts/available-variables`.
- A doc narrativa lista ainda `/contacts/batch-create`, `/contacts/merge`,
  `/contacts/export` e `/contacts/import-csv`, que **não** constam do
  `openapi.yaml` publicado nem foram verificados ao vivo.

Rate limit: **60 req/min** e **10.000 req/dia** (payload máx. 1 MB). Erros
tratados: 400, 401, 402 (quota), 403, 404, 406, 429 (retry com backoff) e 5xx.

## Scripts auxiliares

- `scripts/list-contacts.sh [api-key] [--search <termo>] [--tag <t>]… [--agent <id>] [--status <s>] [--priority <p>] [--channel <c>] [--crm-scenario <id>] [--crm-step <id>] [--start-date <iso>] [--end-date <iso>] [--has-email] [--has-phone] [--limit <1-100>] [--cursor <c>] [--offset <n>] [--all]`
  — lista contatos em tabela (id, nome, e-mail, telefone, criação). `--all` segue
  o `nextCursor` até o fim e deduplica por id.
- `scripts/create-contact.sh [api-key] [--id <id>] [--email <e>] [--phone <fone>] [--first-name <n>] [--last-name <s>] [--user-id <ext>] [--picture <url>] [--metadata '<json>'] [--json '<extra>']`
  — cria (sem `--id`) ou atualiza (com `--id`) um contato. `--user-id` grava o
  campo `externalId`; `--json` mescla um objeto JSON extra no payload.
- `scripts/delete-contact.sh [api-key] <contact-id> [--search <termo>]`
  — mostra o contato encontrado na busca prévia, pede confirmação
  (`CV_YES=1` pula em automação) e executa o `DELETE`.
- `scripts/list-contact-variables.sh [api-key] <contact-id|conversation-id>`
  — lista as variáveis (`varName`, `varValue`, `source`).
- `scripts/set-contact-variable.sh [api-key] <contact-id> --key <chave> (--value <texto> | --value-json <json>) [--source human|ai] [--update]`
  — cria/atualiza uma variável (`POST`; `--update` usa `PUT`, mesmo upsert).
- `scripts/delete-contact-variable.sh [api-key] <contact-id> (--key <chave> | --all-variables)`
  — remove uma variável ou todas, com confirmação.

Saída: resultado em **stdout**, diagnósticos em **stderr**. Com `CV_JSON=1` o
stdout contém **somente JSON**. Operações destrutivas exigem confirmação;
`CV_YES=1` aprova automaticamente (automação).

## Exemplos

```bash
# localizar um contato
./contacts/scripts/list-contacts.sh "$CHATVOLT_API_KEY" --search cliente@exemplo.com

# contatos de um agente, com e-mail, em página única
./contacts/scripts/list-contacts.sh "$CHATVOLT_API_KEY" --agent "$AGENT_ID" --has-email --limit 50

# todas as páginas (segue nextCursor)
./contacts/scripts/list-contacts.sh "$CHATVOLT_API_KEY" --tag vip --all

# criar e depois atualizar
./contacts/scripts/create-contact.sh "$CHATVOLT_API_KEY" --email cliente@exemplo.com --first-name Ana --phone 5511988887777
./contacts/scripts/create-contact.sh "$CHATVOLT_API_KEY" --id contact_abc123 --last-name Souza

# variáveis do contato
./contacts/scripts/list-contact-variables.sh "$CHATVOLT_API_KEY" contact_abc123
./contacts/scripts/set-contact-variable.sh "$CHATVOLT_API_KEY" contact_abc123 --key plano --value pro
./contacts/scripts/set-contact-variable.sh "$CHATVOLT_API_KEY" contact_abc123 --key pedidos --value-json '[1,2,3]' --source ai
./contacts/scripts/delete-contact-variable.sh "$CHATVOLT_API_KEY" contact_abc123 --key plano

# remover o contato (pede confirmação)
./contacts/scripts/delete-contact.sh "$CHATVOLT_API_KEY" contact_abc123 --search cliente@exemplo.com
```

Exit codes: `0` ok · `1` erro de cliente · `3` quota (402) · `4` rede ·
`5` servidor · `130` cancelado.
