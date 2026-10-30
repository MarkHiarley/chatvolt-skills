---
name: chatvolt-artifacts
description: >
  Gerencia o catálogo de artefatos do Chatvolt pela API: lista, busca e detalha
  artefatos, cria/atualiza/remove artefatos e categorias e administra as mídias
  vinculadas (listar, enviar arquivo por multipart, atualizar metadados, remover).
  Use quando precisar consultar o que já existe de conteúdo reutilizável
  (imagens, vídeos, documentos) na organização, organizar categorias ou publicar
  e vincular uma mídia a um artefato.
---

# Chatvolt Artifacts — catálogo, categorias e mídias

Você me diz o que quer consultar ou publicar no catálogo (um termo de busca, uma
categoria, um artefato ou um arquivo), e eu uso a API de artefatos do Chatvolt
para listar, detalhar, criar, atualizar, remover e enviar mídias — sempre com
confirmação antes de qualquer escrita.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys) e,
> para criar/atualizar artefatos, um `categoryId` existente (`categories.sh list`).

## Passo 0 — verificar atualizações

Toda vez que esta skill é carregada, rode a checagem antes de operar (leva ~1s e não bloqueia):

```bash
scripts/check-updates.sh
```

Ela compara a doc OpenAPI publicada (docs.chatvolt.ai), as operações da fonte da doc e o código-fonte do Chatvolt com o que as skills conhecem. Se aparecer `MUDOU`, `fora do catálogo` ou `Código-fonte MUDOU`, **avise o usuário** antes de agir e diga o que mudou — a lista vem no próprio relatório. Sem rede, a skill segue normalmente. `CV_UPDATE_CHECK=0` desliga a checagem.

## Como funciona

1. Você informa a **API key** (argumento ou `CHATVOLT_API_KEY`).
2. **Descobrir o que existe:** `categories.sh list` para as categorias e
   `list-artifacts.sh`/`search-artifacts.sh` para os artefatos. `search-artifacts.sh`
   é o caminho para busca por texto, faixa de preço e tipo de mídia.
3. **Inspecionar:** `get-artifact.sh <id> --media` mostra o artefato e as mídias
   vinculadas (a rota de mídias exige `artifact_id`).
4. **Organizar:** `categories.sh create|update|delete` mantém a hierarquia de
   categorias (que a busca usa recursivamente via `categoryIds`).
5. **Publicar/mudar:** `create-artifact.sh`, `update-artifact.sh` e
   `delete-artifact.sh` escrevem no catálogo; `media.sh upload` envia arquivos
   por multipart e vincula a um artefato; `media.sh update|delete` ajusta ou
   remove a mídia.
6. Toda operação de escrita (PUT, PATCH, DELETE) pede confirmação e é pulada com
   `CV_YES=1` em automação.

## API usada

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/artifacts` | Lista artefatos (`{data:[...],total}`) com `categoryId`, `name`, `search` |
| `POST` | `/artifacts` | Cria artefato (exige `name` e `categoryId`) |
| `DELETE` | `/artifacts` | Deleção em lote (`{"ids":[...]}`) → `{count,message}` |
| `GET` | `/artifacts/{id}` | Objeto do artefato na raiz (com `category` e `media`) |
| `PUT` | `/artifacts/{id}` | Atualiza o artefato (substitui os campos editáveis) |
| `DELETE` | `/artifacts/{id}?action=` | `delete` (padrão) ou `toggle` (alterna `isActive`) |
| `GET` | `/artifacts/search` | Busca com `q`, `ids`, preço, categorias e tipos de mídia |
| `GET` | `/artifacts/media` | Lista mídias — **exige `artifact_id`** |
| `POST` | `/artifacts/media/upload` | Upload multipart (`file`, `artifact_id`, `name`) |
| `PATCH` | `/artifacts/media/{id}` | Atualiza `name`, `altDescription`, `isActive` (parcial) |
| `DELETE` | `/artifacts/media/{id}` | Remove a mídia → `{success:true}` |
| `GET`/`POST` | `/artifact-categories` | Lista (array na raiz) / cria categoria (exige `name`) |
| `GET`/`PUT`/`DELETE` | `/artifact-categories/{id}` | Detalha / atualiza / remove categoria |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>` · docs:
<https://chat-volt.mintlify.app/pages/artifacts/reference>

### Formas de resposta (medidas ao vivo em 2026-10-12)

| Rota | Corpo real |
|---|---|
| `GET /artifacts` | `{"data":[Artifact...],"total":12}` (o `total` é o total da organização, não o da página) |
| `GET /artifacts/{id}` | objeto `Artifact` **na raiz** (traz `category`, `media`, `_count.media`) |
| `GET /artifacts/search` | `{"data":[Artifact...],"meta":{"total","page","limit","totalPages","maxMedias"}}` |
| `GET /artifact-categories` | **array na raiz** (cada item traz `_count.artifacts`, `parent`, `children`) |
| `GET /artifacts/media` | **array na raiz** (sem `artifact_id` → `400 {"error":"error invalid request query"}`) |
| `DELETE /artifacts/{id}` | objeto `Artifact` afetado |

`Artifact`: `id`, `organizationId`, `name`, `description`, `price`, `currency`,
`externalUrl`, `customJson`, `categoryId`, `isActive`, `createdAt`, `updatedAt`,
`category`, `media[]`, `_count.media`.
`ArtifactCategory`: `id`, `name`, `description`, `parentId`, `isActive`,
`_count.artifacts`, `parent`, `children[]`.
`ArtifactMedia`: `id`, `artifactId`, `mediaType`, `name`, `s3Key`, `s3Url`,
`altDescription`, `isActive`, `createdAt`, `updatedAt`.

### Parâmetros e limites

- `GET /artifacts`: `categoryId` (exato), `name` (nome **exato**), `search`
  (nome/descrição/id). Paginação por `limit`/`offset` — medido: `limit` padrão
  **10**, `offset` funciona e `page` é **ignorado** nesta rota.
- `POST /artifacts` (`CreateArtifactPayload`): **`name` e `categoryId` são
  obrigatórios**; opcionais `description`, `price` (number), `externalUrl`,
  `customJson` (objeto), `isActive`.
- `PUT /artifacts/{id}` (`UpdateArtifactPayload`): `name`, `description`, `price`,
  `externalUrl`, `customJson`, `categoryId`, `isActive`. O PUT **substitui** o
  artefato — os scripts leem o estado atual e reenviam o conjunto completo de
  campos editáveis antes de aplicar a mudança parcial.
- `GET /artifacts/search`: `q`, `ids`, `minPrice`, `maxPrice`, `categoryIds`
  (inclui subcategorias), `mediaTypes` (`IMAGE,VIDEO,AUDIO,DOCUMENT,OTHER`),
  `maxMedias` (padrão 10, **máx 50**), `includeInactive`, `limit` (padrão 20,
  **máx 100**), `page`. `ids` presente faz a API ignorar `q`.
  Um `mediaTypes` fora do enum **derrubava a rota com HTTP 500** — os scripts
  validam o valor antes de chamar (exit 1).
- `GET /artifacts/media`: `artifact_id` **obrigatório**, `q`, `type`
  (`IMAGE|VIDEO|AUDIO|DOCUMENT|OTHER|all`). `type` inválido também responde 500
  (validado no cliente).
- `POST /artifacts/media/upload` (multipart): `file`, `artifact_id`, `name`
  obrigatórios; `alt_description` opcional. Resposta: `{s3Key, fileUrl,
  artifactMedia}`.
- `PATCH /artifacts/media/{id}` é **parcial**: envie só `name`, `altDescription`
  (é `altDescription`, não `alt`) e/ou `isActive`.
- `DELETE /artifacts/{id}` é permanente e leva as mídias junto; `action=toggle`
  apenas alterna `isActive`.
- `DELETE /artifact-categories/{id}` → `{message}`; os artefatos da categoria
  ficam sem categoria (reatribua antes com `PUT /artifacts/{id}`).
- Rate limit **60 req/min** e **10.000 req/dia**, payload máximo **1 MB**
  (`X-RateLimit-*`, `Retry-After`). Códigos tratados pelos scripts: `400`, `401`,
  `402` (quota), `403`, `404`, `406`, `429`, `5xx`.

### Disponibilidade e divergências da doc

- `/artifacts`, `/artifacts/search`, `/artifact-categories` e `/artifacts/media`
  estão disponíveis no ambiente de teste (verificado em 2026-10-12). Não há rota
  desta família ausente por plano/organização.
- Id inexistente responde **404** (`{"error":"NOT_FOUND"}`) em
  `GET /artifacts/{id}` e `GET /artifact-categories/{id}`.
- As páginas narrativas de artefatos estão **erradas** no contrato: descrevem
  `title`/`type`/`content` e `category` como string (o real é `name` +
  `categoryId` + `category` objeto), listam `POST /artifacts/search` (o real é
  **GET**) e exibem `contentUrl`/`limit`/`offset` em `GET /artifacts` — o
  `openapi.yaml` e o comportamento medido são a fonte da verdade.

## Scripts auxiliares

- `scripts/list-artifacts.sh [api-key] [--category <id>] [--name <nome>] [--search <termo>] [--limit N] [--offset N] [--all]`
  — lista artefatos (`{data,total}`); `--all` pagina por `offset` até cobrir o
  total informado pela API.
- `scripts/get-artifact.sh [api-key] <artifact-id> [--media]`
  — detalha um artefato; com `--media` também lista as mídias vinculadas.
- `scripts/create-artifact.sh [api-key] --name <nome> --category <id> [--description <d>] [--price <n>] [--external-url <u>] [--active <bool>] [--json '<objeto>']`
  — cria um artefato (valida `name`/`categoryId` antes de chamar a API).
- `scripts/update-artifact.sh [api-key] <artifact-id> [--name <n>] [--description <d>] [--category <id>] [--price <n>] [--external-url <u>] [--active <bool>] [--json '<objeto>']`
  — lê o artefato, mescla os campos informados e aplica o `PUT` (com confirmação).
- `scripts/delete-artifact.sh [api-key] <artifact-id> [--toggle]` ou `--ids <id1,id2>`
  — remove (ou alterna `isActive` de) um artefato, ou deleta em lote via
  `DELETE /artifacts`. Sempre mostra o que será afetado e pede confirmação.
- `scripts/search-artifacts.sh [api-key] [--q <termo>] [--ids <a,b>] [--category-ids <a,b>] [--media-types <tipos>] [--min-price <n>] [--max-price <n>] [--max-medias <n>] [--include-inactive] [--limit N] [--page N] [--all]`
  — busca avançada; `--all` percorre as páginas usando `meta.totalPages`.
- `scripts/categories.sh [api-key] list|get <id>|create --name <n> [--description <d>] [--parent <id>]|update <id> [campos]|delete <id>`
  — CRUD de categorias (list/get são leitura; update/delete confirmam).
- `scripts/media.sh [api-key] list --artifact <id> [--q <termo>] [--type <tipo>] | upload --artifact <id> --file <caminho> [--name <n>] [--alt <texto>] | update <media-id> [--name <n>] [--alt <texto>] [--active <bool>] | delete <media-id>`
  — mídias: listar (exige `--artifact`), enviar arquivo por multipart, atualizar
  metadados e remover.

Saída: resultados em **stdout**, diagnósticos em **stderr**; com `CV_JSON=1` o
stdout contém **somente JSON**.

## Exemplos

```bash
# Categorias disponíveis
./artifacts/scripts/categories.sh "$CHATVOLT_API_KEY" list

# Busca por texto, com preço e tipos de mídia
./artifacts/scripts/search-artifacts.sh "$CHATVOLT_API_KEY" --q "sensor" --media-types IMAGE,VIDEO --limit 5

# Artefato + mídias vinculadas
./artifacts/scripts/get-artifact.sh "$CHATVOLT_API_KEY" cmt3e7mgq06qf7w62kbg0kg3k --media

# Criar artefato numa categoria existente
./artifacts/scripts/create-artifact.sh "$CHATVOLT_API_KEY" --name "Relatório OMP" --category cmt3e7c8u05a9r6xg5ehh4n7q --description "relatório de teste"

# Enviar um arquivo e vinculá-lo ao artefato
./artifacts/scripts/media.sh "$CHATVOLT_API_KEY" upload --artifact cmt3e7mgq06qf7w62kbg0kg3k --file ./relatorio.pdf --alt "Relatório mensal"
```
