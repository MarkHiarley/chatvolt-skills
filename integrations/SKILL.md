---
name: chatvolt-integrations
description: >
  Envia mensagens por canais externos integrados ao Chatvolt — Z-API (WhatsApp),
  Zapper e Twilio (SMS) — pela API pública. Use quando precisar disparar um SMS
  ou uma mensagem de WhatsApp a partir de uma instância já conectada na
  organização, sempre com confirmação explícita de envio real.
---

# Chatvolt Integrations — Z-API, Zapper e Twilio

Você me diz qual integração está conectada na sua organização (instância Z-API,
instância Zapper ou número Twilio) e para qual telefone quer falar, e eu monto e
disparo a mensagem pela API do Chatvolt. A mensagem é registrada na conversa do
contato automaticamente.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys),
> a integração já configurada na organização e o identificador dela:
> `instanceId` da Z-API, `id` da instância Zapper ou o `ownerPhone` verificado
> na conta Twilio.

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Regras críticas

1. **Estes três endpoints enviam mensagem de verdade.** Não existe modo de
   teste: a chamada vai para o telefone do destinatário real e fica no histórico
   do contato. Nunca aponte para o número de um cliente.
2. Todo script exige **`--yes`** explícito (ou `CV_YES=1` em automação) e
   imprime um aviso de envio real em `stderr` **antes** da requisição. Sem o
   `--yes`, o script sai com código 1 e **nada** é enviado.
3. Telefones no formato **DDI + DDD, só dígitos**, sem `+` nem espaços
   (ex.: `5511999998888`). Valores com `/` ou espaços são recusados porque
   entrariam no caminho da URL.
4. Campos extras (anexos, por exemplo) vão por `--json '<objeto>'`, mesclado no
   corpo da requisição. O valor é passado ao Python por `argv`, nunca por
   interpolação de string.

## Como funciona

1. Você informa a **API key** (argumento ou `CHATVOLT_API_KEY`) e os ids da
   integração.
2. Eu valido os argumentos, monto o corpo em JSON e mostro o aviso de envio real.
3. Disparo o `POST` correspondente; a resposta é o objeto `Message` criado
   (`id`, `conversationId`, `from`, `externalId`, `createdAt`).
4. Erros viram mensagem acionável em `stderr`: `400` (corpo/path inválido),
   `402` (**recurso premium** — a organização não tem assinatura ativa; exit 3),
   `403` (API key/organização), `404` (instância ou telefone não encontrado),
   `500`.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `POST` | `/twilio/{ownerPhone}/{contactPhone}/message` | Envia SMS via integração Twilio |
| `POST` | `/zapi/{instanceId}/{contactPhone}/message` | Envia WhatsApp (texto e/ou anexos) via Z-API |
| `POST` | `/zapper/instances/{id}/message` | Envia mensagem (texto e/ou anexos) via Zapper |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>`
Docs: <https://chat-volt.mintlify.app/pages/integrations/zapi>,
<https://chat-volt.mintlify.app/pages/integrations/zapper>,
<https://chat-volt.mintlify.app/pages/integrations/twilio> ·
contrato: <https://chat-volt.mintlify.app/openapi.yaml>

### Corpos aceitos (openapi.yaml)

`POST /twilio/{ownerPhone}/{contactPhone}/message`

| Campo | Tipo | Observação |
|-------|------|------------|
| `message` | string | texto do SMS; ~160 caracteres por parte (a Twilio divide mensagens maiores) |

`POST /zapi/{instanceId}/{contactPhone}/message`

| Campo | Tipo | Observação |
|-------|------|------------|
| `message` | string | texto da mensagem |
| `attachments[]` | array | itens `{url (obrigatório), name?, mimeType?}` |

`POST /zapper/instances/{id}/message`

| Campo | Tipo | Observação |
|-------|------|------------|
| `message` | string | texto da mensagem |
| `contactPhone` | string | destinatário — o contrato declara aqui, não no path |
| `attachments[]` | array | itens `{url (obrigatório), name?, mimeType?}` |

> Divergência da doc narrativa: a página do Zapper mostra `"to"` no corpo, mas o
> `openapi.yaml` define `contactPhone`. O `send-zapper.sh` aceita `--to` como
> **apelido** de `--contact-phone` e sempre envia o campo `contactPhone`.

### Resposta e limites

- `200` → objeto **`Message` na raiz** (`{id,text,html,from,conversationId,
  externalId,contactId,userId,agentId,metadata,read,createdAt,updatedAt}`), sem
  envelope `{data}`.
- `400` corpo/path inválido · `402` premium sem assinatura ativa (exit 3) ·
  `403` não autorizado · `404` instância/telefone não encontrado · `500` erro
  interno (só a rota da Z-API documenta 500).
- Rate limit global: **60 req/min**, **10.000 req/dia**, payload máximo 1 MB.
  Um `429` é reprocessado com backoff pelo helper HTTP (`CV_MAX_RETRIES`,
  `CV_RETRY_WAIT`).

### Disponibilidade e como esta skill foi validada

- `/twilio/*`, `/zapi/*` e `/zapper/*` **enviam mensagem real** — nunca foram
  disparadas ao vivo no ambiente de teste. O contrato foi conferido contra o
  `openapi.yaml` publicado e o caminho feliz mais os erros (404 e 402) são
  exercitados **só no stub offline** (`tests/stub-fixtures/integrations.json`).
- Os casos `live` desta skill executam apenas `--help` (nenhuma requisição sai).
- Dicas de operação: a instância Z-API precisa estar conectada/ativa; o WhatsApp
  oficial via Z-API exige número aprovado e template para o primeiro contato; o
  `ownerPhone` precisa ser um número verificado na conta Twilio.

## Scripts auxiliares

- `scripts/send-twilio.sh [api-key] --owner-phone <num> --contact-phone <num>
  (--message <texto> | --json '<json>') --yes`
  — envia SMS via Twilio (`POST /twilio/{ownerPhone}/{contactPhone}/message`).
- `scripts/send-zapi.sh [api-key] --instance <id> --contact-phone <num>
  (--message <texto> | --json '<json>') --yes`
  — envia WhatsApp via Z-API (`POST /zapi/{instanceId}/{contactPhone}/message`);
  anexos vão em `--json '{"attachments":[{"url":"…","mimeType":"…"}]}'`.
- `scripts/send-zapper.sh [api-key] --instance <id> --contact-phone <num>
  (--message <texto> | --json '<json>') --yes`
  — envia via Zapper (`POST /zapper/instances/{id}/message`); `--to` é apelido de
  `--contact-phone`.

Saída: resultados em **stdout**, avisos/diagnósticos em **stderr**. Com
`CV_JSON=1` o stdout contém **somente JSON**.
Exit codes: `0` ok · `1` erro de cliente · `3` quota/premium (402) · `4` rede ·
`5` servidor · `130` cancelado.

## Exemplos

```bash
# SMS (Twilio) — confirma o envio real com --yes
./integrations/scripts/send-twilio.sh "$CHATVOLT_API_KEY" \
  --owner-phone 5511999998888 --contact-phone 5511988887777 \
  --message "Seu código de verificação é 1234" --yes

# WhatsApp (Z-API) com anexo
./integrations/scripts/send-zapi.sh "$CHATVOLT_API_KEY" \
  --instance inst_123 --contact-phone 5511988887777 \
  --message "Segue a foto do pedido" \
  --json '{"attachments":[{"url":"https://exemplo.com/foto.jpg","mimeType":"image/jpeg"}]}' --yes

# Zapper
./integrations/scripts/send-zapper.sh "$CHATVOLT_API_KEY" \
  --instance inst_123 --contact-phone 5511988887777 \
  --message "Olá! Mensagem enviada via Zapper" --yes

# Modo automação: stdout só com JSON
CV_JSON=1 CV_YES=1 ./integrations/scripts/send-zapi.sh "$CHATVOLT_API_KEY" \
  --instance inst_123 --contact-phone 5511988887777 --message "olá"
```

Para outros canais e formatos ricos (botões, listas, template) use a skill
`chatvolt-whatsapp`; para uma rota crua qualquer, `chatvolt-api-call`.
