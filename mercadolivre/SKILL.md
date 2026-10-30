---
name: chatvolt-mercadolivre
description: >
  Lista, conta, busca e sincroniza os produtos do Mercado Livre integrados ao
  Chatvolt pela API. Use para consultar o catálogo do Mercado Livre de um
  agente, saber quantos produtos estão sincronizados ou disparar uma nova
  sincronização.
---

# Chatvolt Mercado Livre

Você me diz qual agente (e qual provedor do Mercado Livre) quer consultar, e eu
listo o catálogo sincronizado, conto os produtos, faço busca fuzzy pelo termo
que você passar ou disparo uma nova sincronização com o Mercado Livre.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys),
> um `agentId` **com a integração do Mercado Livre conectada** e, para
> `/mercadolivre/products`, o `serviceProviderId` dessa integração.

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Como funciona

1. Você informa a **API key** (1º argumento ou `CHATVOLT_API_KEY`) e o
   **agentId** (2º argumento ou `CHATVOLT_AGENT_ID`).
2. **Listar** (`list-products.sh`) exige também `--service-provider <id>`; a
   resposta vem paginada (`products`, `total`, `page`, `perPage`).
3. **Contar** (`count-products.sh`) aceita o agentId opcional: sem ele conta o
   total da organização, com ele conta só o agente.
4. **Buscar** (`get-products.sh`) usa o filtro fuzzy da rota legada
   `/mercadolivre/get-products` (`query`, `threshold`, `maxResults`, entre outros).
5. **Sincronizar** (`sync-products.sh`) dispara uma sincronização real e só roda
   com `--yes` explícito.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/mercadolivre/products` | Lista produtos sincronizados (exige `agentId` + `serviceProviderId`) |
| `GET` | `/mercadolivre/products/count` | Conta produtos (total da organização ou por agente) |
| `GET` | `/mercadolivre/get-products` | Lista/busca produtos com filtro fuzzy (exige `agentId`) |
| `POST` | `/mercadolivre/products/sync` | Dispara sincronização dos produtos do Mercado Livre |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/integrations/mercadolivre>

### `GET /mercadolivre/products` (listagem paginada)

A doc pública **não** documenta parâmetros nesta rota, mas a API exige dois —
verificado ao vivo em 2026-10-12:

```
GET /mercadolivre/products                                    → 400 {"error":"agentId and serviceProviderId are required"}
GET /mercadolivre/products?agentId=<id>                       → 400 (mesmo erro)
GET /mercadolivre/products?agentId=<id>&serviceProviderId=<id>→ 200 {"products":[],"total":0,"page":1,"perPage":8}
```

| Parâmetro | Observações |
|-----------|-------------|
| `agentId` | obrigatório |
| `serviceProviderId` | obrigatório |
| `page` | página (default 1) |
| `perPage` | itens por página; a API usa **8** quando omitido e devolve o valor escolhido no campo `perPage` da resposta (testado com 1, 20, 50, 100 e 500) |

Resposta: `{"products":[…],"total":N,"page":P,"perPage":M}` — **não** usa o
envelope `{data,success,error}`.

### `GET /mercadolivre/products/count` (contagem)

Resposta: `{"count":N}`. O `agentId` é **opcional** e funciona como filtro:

```
GET /mercadolivre/products/count                          → 200 {"count":54721}  (organização)
GET /mercadolivre/products/count?agentId=<id>             → 200 {"count":0}      (escopo do agente)
```

`serviceProviderId` **não** filtra a contagem (é ignorado: devolve o total da
organização).

### `GET /mercadolivre/get-products` (busca fuzzy, rota legada)

Exige `agentId` (`400 {"error":"Agent ID is required"}` sem ele). Parâmetros de
query (o script só envia os que você informar; os demais ficam no default da API):

| Parâmetro | Tipo / default (openapi) | Descrição |
|-----------|--------------------------|-----------|
| `agentId` | string, **obrigatório** | agente com o Mercado Livre conectado |
| `query` | string | termo da busca fuzzy |
| `threshold` | number, `0.3` | relevância mínima |
| `maxResults` | integer | máximo de resultados |
| `sortByRelevance` | boolean, `true` | ordenar por relevância |
| `typoTolerance` | integer `1` no openapi; a doc narrativa diz boolean | tolerância a erros de digitação |
| `caseSensitive` | boolean, `false` | busca sensível a maiúsculas |
| `partialMatch` | boolean, `true` | aceitar correspondência parcial |

Resposta: `{"products":[…]}` (a doc avisa que a rota não usa o envelope padrão;
o script também aceita um array na raiz).

**Disponibilidade medida ao vivo (2026-10-12, organização de teste):** com o
`agentId` da organização a rota responde
`404 {"error":"Mercado Livre service provider not found for this agent"}` — não
há integração do Mercado Livre conectada nessa organização, e não há parâmetro
alternativo. O `get-products.sh` reconhece esse 404 e explica que falta conectar
a integração (exit 1), em vez de devolver o erro cru.

### `POST /mercadolivre/products/sync` (sincronização)

**Operação de escrita:** dispara uma sincronização real do catálogo. A doc
mostra um POST sem corpo e não documenta parâmetros; o script envia
`agentId`/`serviceProviderId` como query **somente quando informados** e só
monta corpo com `--json '<objeto>'`. Exige a flag `--yes` (variável `CV_YES=1`
**não** substitui a flag). A sonda ao vivo não foi feita por ser escrita.

### Limites e erros

Rate limit **60 req/min** e **10.000 req/dia**, payload máximo 1 MB. Erros
tratados pelos scripts: `400` (parâmetros ausentes/inválidos), `401/403` (key ou
permissão), `402` (quota do plano, exit 3), `404`, `406`, `429` (backoff
automático) e `5xx` (exit 5). Exit codes: `0` ok · `1` erro de cliente · `3`
quota · `4` rede · `5` servidor · `130` cancelado.

## Scripts auxiliares

- `scripts/list-products.sh <api-key> <agent-id> --service-provider <id> [--page N] [--per-page N] [--all] [--full]`
  — lista os produtos em tabela (id, título, preço, moeda, estoque, link).
  `--per-page` usa 50 por padrão; `--all` percorre as páginas até cobrir
  `total`; `--full` imprime o JSON completo da resposta.
- `scripts/count-products.sh <api-key> [agent-id] [--agent <id>]`
  — conta os produtos (`{"count":N}`); sem agent-id usa o total da organização.
- `scripts/get-products.sh <api-key> <agent-id> [--query <termo>] [--threshold <float>] [--max-results N] [--sort-by-relevance <bool>] [--typo-tolerance <n|bool>] [--case-sensitive <bool>] [--partial-match <bool>]`
  — busca fuzzy pelos produtos sincronizados; trata o 404 de agente sem
  integração com mensagem acionável.
- `scripts/sync-products.sh <api-key> --yes [--agent <id>] [--service-provider <id>] [--json '<extra>']`
  — dispara a sincronização (avisa em stderr antes de enviar).

Saída: resultados em **stdout**, diagnósticos em **stderr**. Com `CV_JSON=1` o
stdout contém **somente JSON** (array de produtos em `list-products.sh` e
`get-products.sh`, objeto `{"count":N}` em `count-products.sh` e a resposta crua
em `sync-products.sh`).

## Exemplos

```bash
./mercadolivre/scripts/count-products.sh "$CHATVOLT_API_KEY"
./mercadolivre/scripts/count-products.sh "$CHATVOLT_API_KEY" "$CHATVOLT_AGENT_ID"
./mercadolivre/scripts/list-products.sh "$CHATVOLT_API_KEY" "$CHATVOLT_AGENT_ID" --service-provider sp-1 --per-page 20
./mercadolivre/scripts/get-products.sh "$CHATVOLT_API_KEY" "$CHATVOLT_AGENT_ID" --query "panela de pressão" --max-results 5
./mercadolivre/scripts/sync-products.sh "$CHATVOLT_API_KEY" --agent "$CHATVOLT_AGENT_ID" --yes
```
