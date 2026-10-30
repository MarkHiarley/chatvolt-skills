---
name: chatvolt-prompt-adjust
description: >
  Ajusta a configuração de um agente Chatvolt pela API — system prompt, modelo
  e temperatura — mostrando o estado atual, o diff e o antes/depois, pedindo
  confirmação antes de aplicar e testando o resultado. Também liga/desliga o
  webhook dos canais do agente. Use quando o agente responde mal, precisa de
  outro modelo/temperatura ou quando for preciso ativar/desativar um serviço de
  mensageria.
---

# Chatvolt — Prompt Adjust

Você me diz qual agente deve mudar e o que deve mudar — o system prompt, o
modelo ou a temperatura — e eu leio a configuração atual, mostro o diff ou o
antes/depois, **peço confirmação**, aplico via `PATCH /agents/{id}` e testo o
resultado com uma query real. Também ligo/desligo o webhook de um serviço de
mensageria (WhatsApp, Telegram, Z-API, Instagram) do agente.

> **Pré-requisitos:** chave de API do Chatvolt
> (https://app.chatvolt.ai/settings/api-keys) e o ID do agente
> (`CHATVOLT_API_KEY` e `CHATVOLT_AGENT_ID` também são aceitos por ambiente).

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Como funciona

1. Você informa a **API key** e o **ID do agente**.
2. Me diz o que quer fazer:
   - **Ver a configuração atual** — nome, modelo, temperatura, system prompt completo e tools (`get-agent.sh`);
   - **Editar o system prompt** — você entrega o novo texto/arquivo, eu mostro o diff linha a linha e o tamanho antes/depois (`update-prompt.sh`);
   - **Trocar o modelo** — o nome é validado contra a lista oficial; se não existir, mostro 5 sugestões próximas (`list-models.sh`, `update-model.sh`);
   - **Ajustar a temperatura** — faixa 0.0–1.0 (`update-temperature.sh`);
   - **Ligar/desligar o webhook de um canal** (`toggle-webhook.sh`);
   - **Testar o comportamento** — envio uma query real e mostro a resposta, as fontes e o `conversationId` (`test-query.sh`);
   - **Fluxo completo** — config atual, teste baseline, mudança, reteste e relatório antes/depois (`adjust.sh`).
3. Toda alteração é **confirmada** e, no caso do prompt, acompanhada de **diff**;
   depois do `PATCH` eu mostro o valor novo que a API devolveu.
4. `CV_YES=1` pula as confirmações (automação); `CV_JSON=1` imprime somente JSON
   em stdout.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents/{id}` | Detalhes do agente (objeto na raiz) |
| `GET` | `/agents/{id}/tools` | Tools do agente (array na raiz) |
| `GET` | `/agents/models` | Lista oficial de modelos (público, array na raiz) |
| `PATCH` | `/agents/{id}` | Atualiza `systemPrompt`, `modelName`, `temperature`, metadados e `tools[]` |
| `PATCH` | `/agents/{id}/webhook?type=&enabled=` | Toggle do webhook de um serviço (sem body) |
| `POST` | `/agents/{id}/query` | Envia uma query de teste (cria uma conversa real, canal `api`) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/agents/reference> e
<https://chat-volt.mintlify.app/pages/agents/webhook>

### Campos aceitos no `PATCH /agents/{id}`

| Campo | Tipo | Observação |
|---|---|---|
| `systemPrompt` | string | System prompt completo (substituição integral, não é patch textual) |
| `modelName` | string | Precisa existir em `GET /agents/models` |
| `temperature` | number | 0.0–1.0 (padrão prático: 0.0–0.2 determinístico, 0.3–0.6 equilibrado, 0.7–1.0 criativo) |
| `name`, `description` | string | Metadados do agente |
| `visibility` | string | `private` etc. |
| `handle` | string | Identificador público |
| `interfaceConfig` | object | Configurações de interface |
| `enableInactiveHours`, `inactiveHours` | boolean / object | Horário de inatividade |
| `tools[]` | array | **Estado final** — ver aviso abaixo |

> **ATENÇÃO — `tools[]` é estado FINAL, não incremental.** O array enviado em
> `PATCH /agents/{id}` **substitui toda a lista de tools do agente**: uma tool com
> `id` é atualizada, uma tool sem `id` é criada e **qualquer tool ausente do array
> é REMOVIDA**. Para mexer em tools sem perder as existentes, leia a lista atual
> com `GET /agents/{id}/tools` (ou a skill `chatvolt-tools-update`) e reenvie o
> array completo. Os scripts desta skill **não** enviam `tools[]`, então não
> alteram as tools do agente.

### Modelos

A lista de modelos **muda com o tempo** (novos modelos entram, antigos saem) e
por isso **não é fixada** nesta documentação. Rode:

```bash
scripts/list-models.sh "$CHATVOLT_API_KEY" [--filter <regex>] [--tools-only] [--vision-only]
```

A tabela traz `model_name`, descrição, visão (`hasVision`) e tool-calling
(`isToolCallingSupported`). Use o `model_name` exato em `update-model.sh` ou em
`--model` do `test-query.sh`. O `update-model.sh` rejeita modelo desconhecido e
mostra 5 sugestões próximas.

### Webhook: `PATCH /agents/{id}/webhook?type=&enabled=`

| Parâmetro | Valores | Observação |
|---|---|---|
| `type` | `whatsapp` · `telegram` · `zapi` · `instagram` | Serviço do agente |
| `enabled` | `true` · `false` | `true` liga, `false` desliga |

- É um **toggle de status**, **sem body** — a URL do webhook é configurada na
  plataforma, não por esta rota. O antigo `POST /agents/{id}/webhook` com JSON
  **não existe** (404).
- Se o agente não tiver o service provider conectado, a API responde
  `404 {"error":"ServiceProvider not found for this agent."}` — o script mostra
  isso de forma legível.
- Para `instagram`, o toggle também controla `answerDms` e `answerComments` do
  agente.

### Limites e erros

- Rate limit: **60 req/min** e 10.000 req/dia (cabeçalhos `X-RateLimit-*`,
  `Retry-After`); payload máximo de **1 MB**.
- `GET /agents/models` é público; as demais rotas exigem `Authorization: Bearer`.
- Erros comuns: `400` requisição inválida · `401`/`403` key inválida ·
  `402` quota do plano · `404` não encontrado · `406` sessão de canal expirada ·
  `429` rate limit · `5xx` erro interno.

## Scripts auxiliares

- `scripts/get-agent.sh <api-key> <agent-id> [--prompt-only] [--no-tools]` — configuração atual + system prompt completo + tabela de tools.
- `scripts/list-models.sh <api-key> [--filter <regex>] [--tools-only] [--vision-only]` — tabela oficial de modelos (única fonte de nomes válidos).
- `scripts/update-prompt.sh <api-key> <agent-id> (--file <path>|--text <text>|--stdin)` — diff (difflib) + confirmação + `PATCH`; imprime o tamanho novo.
- `scripts/update-model.sh <api-key> <agent-id> <model> [--force]` — valida contra `/agents/models` (5 sugestões se desconhecido), confirma e aplica.
- `scripts/update-temperature.sh <api-key> <agent-id> <0.0-1.0> [--force]` — valida a faixa, confirma e aplica.
- `scripts/toggle-webhook.sh <api-key> <agent-id> <whatsapp|telegram|zapi|instagram> <on|off>` — toggle do webhook (sem body); imprime a resposta da API.
- `scripts/test-query.sh <api-key> <agent-id> <query> [--temp N] [--model M] [--system-prompt-file <path>]` — query de teste; imprime resposta, fontes e o `conversationId` criado.
- `scripts/adjust.sh <api-key> <agent-id> <query> [--change prompt|model|temperature] [--file <path>|--text <text>|--stdin|--value <v>] [--no-retest]` — fluxo completo com relatório antes/depois.

## Convenções

- Chave: primeiro argumento ou `CHATVOLT_API_KEY`.
- `CV_JSON=1` — somente JSON em stdout (diagnósticos em stderr).
- `CV_YES=1` — aprova as confirmações (use em automação).
- `CV_API_BASE` — sobrescreve a base URL (útil para stub de teste).
- Exit codes: `0` ok · `1` erro de cliente · `3` quota (402) · `4` rede ·
  `5` servidor · `130` cancelado.
- Nada é gravado em arquivo temporário permanente: os arquivos de trabalho usam
  `mktemp -d` e são removidos ao final.
