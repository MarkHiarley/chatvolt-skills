---
name: chatvolt-tools-update
description: >
  Gerencia as ferramentas (tools) de agentes Chatvolt via API: listar, criar,
  atualizar e deletar tools dos tipos http, datastore, form e demais tipos
  aceitos. Use quando precisar conectar uma API externa, ligar uma base de
  conhecimento, ver o que já está configurado ou remover uma ferramenta.
---

# Chatvolt Tools

Gerencia as ferramentas (tools) de um agente Chatvolt. Você me diz **o que quer fazer** com as tools do agente e eu executo a chamada correta na API.

> **Pré-requisitos:** chave de API (https://app.chatvolt.ai/settings/api-keys) e o **ID do agente**.

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Como funciona

1. Você informa a **API key** e o **ID do agente**.
2. Escolhe a operação: **listar/ver**, **criar**, **atualizar** ou **deletar** uma tool.
3. Para criar/atualizar, você fornece a configuração da tool em JSON.
4. Operações destrutivas (delete, patch) mostram o estado atual e pedem confirmação.

> **Atenção:** não existe endpoint de leitura individual de tool. `GET /agents/{agentId}/tools/{toolId}` responde **404**. Para "ver uma tool", filtre a listagem (`list-tools.sh --id <toolId> --full`).

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/agents/{agentId}/tools` | Lista as tools do agente (array na raiz) |
| `POST` | `/agents/{agentId}/tools` | Cria uma tool (resposta 2xx com o objeto da tool na raiz) |
| `PATCH` | `/agents/{agentId}/tools/{toolId}` | Atualiza uma tool (o corpo **exige** o campo `type`) |
| `DELETE` | `/agents/{agentId}/tools/{toolId}` | Remove uma tool (`{"success":true,"toolId":"..."}`) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs: <https://chat-volt.mintlify.app/pages/agents/reference>

### Tipos de tool

Tipos **documentados** (aparecem na doc):

| Tipo | Campo-chave |
|------|-------------|
| `http` | `config` (nome, descrição, url, method, headers, body...) |
| `datastore` | `datastoreId` |
| `form` | `formId` |
| `lead_capture` | `config` |
| `api_tool` | `config` |
| `mark_as_resolved` | `config` |
| `request_human` | `config` |
| `delayed_responses` | `config` |
| `follow_up_messages` | `config` |

Tipos **observados ao vivo** nesta organização (não aparecem na doc de CRUD):

| Tipo | Observação |
|------|------------|
| `quick_reply_buttons` | botões de resposta rápida; `config.mode` aceita `llm_decides` |
| `artifact_category_selector` | seletor de categoria de artefato |

O validador ao vivo aceita ainda `connector`, `agent` e `channel_transfer` — e **rejeita `api_tool`** com `400 invalid discriminator value`. Ou seja: a doc e o validador divergem; em caso de dúvida, faça o `POST` e leia o erro.

Discriminadores aceitos hoje pelo validador da API:
`http | lead_capture | datastore | connector | agent | form | mark_as_resolved | request_human | delayed_responses | follow_up_messages | artifact_category_selector | channel_transfer | quick_reply_buttons`

### Campos de config HTTP

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `config.name` | Sim | Nome único e descritivo |
| `config.description` | Sim | Descrição usada pelo agente para decidir quando chamar |
| `config.url` | Sim | URL (suporta `:variavel` para path variables) |
| `config.method` | Sim | `GET`, `POST`, `PUT`, `DELETE`, `PATCH` |
| `config.withApproval` | Não | Exige aprovação humana antes de executar |
| `isRaw` | Não | Usa o corpo cru (raw cURL); também aceito em `config.isRaw` |
| `config.headers` | Não | Array de `{key, value, isUserProvided, description, acceptedValues}` |
| `config.body` | Não | Array key/value para urlencoded/form-data |
| `config.queryParameters` | Não | Parâmetros de query string |
| `config.pathVariables` | Não | Variáveis de path (`{key, value, description}`) |
| `config.hasMaximumToolCalls` | Não | Habilita limite de chamadas |
| `config.maximumToolCalls` | Não | Número máximo de chamadas (quando `hasMaximumToolCalls`) |
| `config.isErrorCountable` | Não | Conta falhas para o limite |
| `config.notifyOnFailure` | Não | Notifica em caso de falha |

> O tipo `datastore` recebe o `datastoreId` **no topo** do objeto (`{"type":"datastore","datastoreId":"..."}`). O `config` enviado junto é descartado pela API (a resposta volta com `config: {}`).

## Scripts auxiliares

Na pasta `scripts/`:

- `list-tools.sh <api-key> <agent-id> [--type <T>] [--id <ID>] [--full]` — lista em tabela (id, type, nome, url/datastoreId/formId, isRaw, hasMaximumToolCalls, maximumToolCalls); `--id` busca uma tool (sai ≠ 0 se não existir); `--full` despeja o JSON.
- `create-tool.sh <api-key> <agent-id> <type> <json|--file <path>|id>` — cria a tool; valida `config.name/description/url/method` no `http`; imprime o `id` criado.
- `update-tool.sh <api-key> <agent-id> <tool-id> <json|--file <path>>` — mostra o estado atual + diff, confirma e aplica o `PATCH` (injeta o `type` atual se o JSON não trouxer).
- `delete-tool.sh <api-key> <agent-id> <tool-id>` — mostra a tool, confirma e deleta.
- `manage-tools.sh <api-key> <agent-id>` — menu interativo (listar, ver, criar, atualizar, deletar, exportar).

Variáveis comuns: `CHATVOLT_API_KEY`/`CHATVOLT_AGENT_ID` (alternativas aos argumentos), `CV_JSON=1` (stdout só JSON), `CV_YES=1` (pula confirmações), `CV_API_BASE` (base URL alternativa).
