---
name: chatvolt-tags
description: >
  Lista, cria e remove as tags da organização no Chatvolt pela API pública
  (GET/POST /tags, POST /tags/delete-by-name, GET /tags/get-visible-tags). Use
  para consultar o catálogo de tags, ver só as tags visíveis no dashboard, criar
  uma tag nova ou apagar uma tag pelo nome — considerando que nesta organização
  as três rotas respondem 404.
---

# Chatvolt Tags

Você me diz o que precisa no catálogo de tags — listar o que existe, ver só as
tags visíveis no dashboard, criar uma tag com nome e cor, ou remover uma tag
pelo nome — e eu executo a chamada correspondente na API pública do Chatvolt,
com confirmação antes de apagar e mensagem explicativa quando a rota responde
404 neste ambiente.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys).
> Nenhum ID extra: as quatro rotas são escopo da organização.

## Aviso de disponibilidade (leia antes de usar)

Medido ao vivo em **2026-10-12** com a chave de teste: as três rotas de tags
respondem **HTTP 404** nesta organização/plano, com corpo **HTML** (a página 404
do dashboard, `text/html`), e não o JSON de erro da API
(`{"error":"NOT_FOUND"}`). Ou seja: a documentação pública lista as rotas, mas a
API não as expõe aqui — **não é falha do script, nem da chave de API, nem da
organização estar vazia**.

Os quatro scripts detectam esse 404 e imprimem em stderr uma explicação com a
rota, o tipo de resposta recebida e as alternativas, saindo com código **1**.
Nada é criado ou removido nesse caso.

- Referência da doc: <https://chat-volt.mintlify.app/pages/tags/reference>
- Estado medido das rotas: `SOURCES.md` §6
- Para revalidar depois (ex.: se o plano passar a expor as rotas):
  `./api-call/scripts/call.sh "$CHATVOLT_API_KEY" GET /tags`
- Alternativa imediata: gerenciar as tags pelo dashboard do Chatvolt.

## Como funciona

1. Você informa a **API key** (primeiro argumento ou `CHATVOLT_API_KEY`).
2. **Listar**: `list-tags.sh` (todas as tags) ou `visible-tags.sh` (só as
   visíveis no dashboard) mostram id, nome e cor.
3. **Criar**: `create-tag.sh --name <nome> [--color <cor>]` envia o corpo exigido
   (`name` obrigatório, `color` opcional) e mostra a tag devolvida pela API.
4. **Remover**: `delete-tag.sh <nome>` pede confirmação explícita (ou
   `--yes`/`CV_YES=1`) porque a operação é destrutiva e não há desfazer.

## API usada

| Método | Endpoint | Descrição | Estado em 2026-10-12 |
|--------|----------|-----------|----------------------|
| `GET` | `/tags` | Lista as tags da organização | 404 (HTML do dashboard) |
| `POST` | `/tags` | Cria tag (`{name, color}`) | 404 (HTML do dashboard) |
| `POST` | `/tags/delete-by-name` | Remove tag pelo nome (`{name}`) | 404 (HTML do dashboard) |
| `GET` | `/tags/get-visible-tags` | Lista as tags visíveis no dashboard | 404 (HTML do dashboard) |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/tags/reference> · contrato publicado:
<https://chat-volt.mintlify.app/openapi.yaml>

### Corpos e respostas (conforme o openapi.yaml)

- `GET /tags` e `GET /tags/get-visible-tags`: resposta `{data:[...], success}`,
  cada item com `id`, `name` e `color`. Nenhum parâmetro de query é documentado —
  os scripts não enviam nenhum.
- `POST /tags`: corpo `{name, color}` (`name` é o único campo obrigatório na
  prática; `color` aceita o valor que o dashboard usa, ex.: `red` ou `#ff0000`).
  A resposta traz a tag criada.
- `POST /tags/delete-by-name`: corpo `{name}`. **Divergência de doc:** a página
  narrativa mostra `DELETE /tags/delete-by-name`, mas o `openapi.yaml` define
  **POST** — o script usa POST (o openapi é a fonte da verdade, ver `SOURCES.md`).
- Não existe `GET /tags/{id}`: para inspecionar uma tag, liste e filtre a saída;
  a remoção por nome é a única operação por identificador humano.

### Envelope das respostas

A doc dessa família mostra `{data, success, error: null}` no sucesso. O helper
`cv_unwrap` só desembrulha quando a chave `error` está **ausente**, então os
scripts aplicam uma segunda passada: com `error` ausente **ou nulo** o payload
(`data`) é extraído; uma resposta já na raiz (array ou objeto) passa intacta.
Assim, tanto `{data:[...], success:true}` quanto `[...]` produzem a mesma saída.

### Limites e erros

Rate limit **60 req/min** e **10.000 req/dia**, payload máximo **1 MB**. Códigos
tratados: `400`, `401`, `402` (quota do plano → exit 3), `403`, `404`, `406`,
`429` (reprocessado com backoff; `CV_MAX_RETRIES`/`CV_RETRY_WAIT`), `5xx`
(exit 5). Falha de rede → exit 4; confirmação recusada → exit 130.

## Scripts auxiliares

- `scripts/list-tags.sh [<api-key>]` — lista as tags da organização
  (`GET /tags`) em tabela (id, nome, cor). Com `CV_JSON=1` imprime só o array JSON.
- `scripts/visible-tags.sh [<api-key>]` — lista as tags visíveis no dashboard
  (`GET /tags/get-visible-tags`), mesmo formato de `list-tags.sh`.
- `scripts/create-tag.sh [<api-key>] --name <nome> [--color <cor>] [--json '<objeto>']`
  — cria a tag (`POST /tags`). `--json` mescla campos extras no corpo (e pode
  sobrescrever `name`/`color`); JSON inválido ou que não seja objeto falha com
  exit 1. Imprime a tag devolvida pela API.
- `scripts/delete-tag.sh [<api-key>] <nome> [--yes]` — remove a tag pelo nome
  (`POST /tags/delete-by-name`). Pede confirmação (pulável com `--yes` ou
  `CV_YES=1`); com `CV_JSON=1` imprime `{"name","success","response"}`.

Saída em **stdout**, diagnósticos em **stderr**; com `CV_JSON=1` o stdout contém
**somente JSON**. Rode qualquer script com `-h`/`--help` para a ajuda completa.
Exit: 0 ok · 1 erro de cliente · 3 quota (402) · 4 rede · 5 servidor · 130 cancelado.
