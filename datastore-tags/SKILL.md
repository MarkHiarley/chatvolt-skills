---
name: chatvolt-datastore-tags
description: >
  Organiza e segmenta as fontes de uma base de conhecimento Chatvolt com
  etiquetas (config.tags) e custom_id. Use quando precisar marcar fontes,
  listar quais etiquetas existem, achar fontes por etiqueta, separar o
  conteúdo por tenant/cliente ou confirmar por que uma busca filtrada não
  retorna nada.
---

# Chatvolt Datastore Tags

Etiquetas e `custom_id` das fontes de uma base. Você me diz **qual fonte marcar** (ou qual
consulta filtrar) e eu leio o estado atual, mostro o antes/depois, aplico e revalido com um GET.

> **Pré-requisitos:** Chave de API (https://app.chatvolt.ai/settings/api-keys), o ID da base
> (`..._v3`) e o ID da fonte. As fontes e as etiquetas aparecem no painel em
> https://app.chatvolt.ai/datastores.

## Como funciona

1. Você informa a **API key**, o **ID da base** e o **ID da fonte**.
2. Eu leio a fonte (`GET /datasources/{id}?idstore={base}`) e mostro as etiquetas atuais, o
   `custom_id`, o status de indexação e o tamanho do texto.
3. Para marcar/desmarcar, eu monto a lista final de etiquetas, mostro o antes/depois e o que
   acontecerá com o texto indexado, peço confirmação e gravo via **upsert** `POST /datasources`
   (não existe `PATCH`/`PUT` de fonte: ambos respondem 404).
4. Eu revalido com um novo `GET`. Nos modos com texto eu espero a reindexação (`nbSynch` precisa
   avançar) e confiro se o `textSize` mudou — se não mudou, aviso que a API ignorou o texto
   enviado e sai 1, porque a troca de conteúdo não é possível em fonte existente.
5. Para provar que a segmentação funciona, rodo uma consulta com
   `filters.custom_ids` e mostro os trechos recuperados.

## Etiqueta × custom_id

Os dois vivem no `config` da **fonte** (a base em si não tem etiquetas nem custom_id), mas
servem para coisas diferentes:

| | Etiqueta (`config.tags`) | `custom_id` (`config.custom_id`) |
|---|---|---|
| Natureza | metadado local, livre (lista de strings) | identificador de segmento (uma string) |
| Afeta a recuperação? | **não** — a busca ignora etiquetas | **sim** — é o filtro `filters.custom_ids` da consulta |
| Como consultar | `list-tags.sh` / `find-by-tag.sh` (filtram no cliente, paginando `/datasources/list`) | `query-verify.sh --custom-id <valor>` |
| Quantos por fonte | vários | um |
| Uso típico | área, status, versão do documento, campanha | tenant, cliente, plano (multi-tenant) |

**Recomendação para multi-tenant:** use `custom_id` — é o único dos dois que a busca respeita.
Com `filters.custom_ids: ["tenant-a"]` a consulta devolve apenas trechos das fontes cujo
`custom_id` é `tenant-a`; com um valor inexistente devolve `[]`. Use etiquetas para organizar o
acervo e achar as fontes depois (a API não filtra por elas).

## API usada

| Método | Endpoint | Descrição |
|---|---|---|
| `GET` | `/datasources/list?datastoreId=&offset=&limit=` | Listar fontes com todo o `config` (aceita `limit` até 100) |
| `GET` | `/datasources/{id}?idstore={datastoreId}` | Ler uma fonte (o `idstore` é obrigatório) |
| `POST` | `/datasources` | Criar fonte e atualizar o `config` (tags/`custom_id`) de uma fonte existente — upsert; **não** substitui o texto indexado |
| `POST` | `/datastores/{id}/query` | Consultar com `filters.custom_ids` / `filters.datasource_ids` |
| `PATCH`/`PUT` | `/datasources/{id}` | **Não existem** — respondem `404 not found` |

Base URL: `https://api.chatvolt.ai` · `Authorization: Bearer <api-key>`
Docs: https://chat-volt.mintlify.app/pages/datastores/reference ·
https://chat-volt.mintlify.app/pages/datastores/query ·
https://chat-volt.mintlify.app/openapi.yaml · https://chat-volt.mintlify.app/pages/errors

### O upsert que altera etiquetas (mecanismo verificado ao vivo)

Como não existe `PATCH` de fonte, alterar etiqueta é reenviar a fonte em `POST /datasources` com o
`id` existente. O que a API faz com esse corpo:

| Corpo enviado em `POST /datasources` | Resultado |
|---|---|
| `id` + `type` + `datastoreId` + `name`, sem `datasourceText` e **sem** `isUpdateText` | `400 INVALID_REQUEST` |
| `isUpdateText: true` e **sem** `datasourceText` | `400 INVALID_REQUEST` |
| `isUpdateText: false` e **sem** `datasourceText` | `200` — `config` (tags/`custom_id`) gravado, texto indexado **intacto** |
| `isUpdateText: true` **com** `datasourceText` | `200` — `config` gravado; o **conteúdo indexado não muda** (ver abaixo) |
| `PATCH`/`PUT` `/datasources/{id}` | `404 not found` |

Corpo do upsert de metadados (o que os scripts enviam):

```json
{ "id": "<id da fonte existente>", "type": "file", "datastoreId": "<base>", "name": "<nome>",
  "isUpdateText": false,
  "config": { "tags": ["a","b"], "custom_id": "tenant-x", "mime_type": "text/plain", "fileSize": 273 } }
```

Avisos importantes:

- **O texto enviado é ignorado em fonte existente.** Com `id` de uma fonte já criada, o
  `datasourceText` é aceito (HTTP 200) mas não substitui o conteúdo indexado: `textSize`,
  `nbChunks` e os trechos devolvidos pela consulta continuam os antigos. Verificado ao vivo com
  o flag `isUpdateText` no top-level e dentro de `config` (as duas posições que aparecem nas
  docs). Para trocar o conteúdo de uma fonte existente: **apague a fonte e recrie**
  (`delete-source.sh` + `add-source.sh` da skill `chatvolt-datastore-add`) — o nome/etiquetas/
  `custom_id` são reaplicados na criação.
- **`config` é substituído, não mesclado.** Campo de `config` omitido no corpo desaparece da
  fonte (observado com `fileSize` e `file_url`). Por isso os scripts releem o `config` atual e
  reenviam todos os campos, trocando apenas `tags`/`custom_id`.
- **Todo upsert conta como sincronização**: `nbSynch` avança e o `hash` muda mesmo quando só o
  `config` foi gravado. Isso **não** significa que o conteúdo mudou — quem prova o conteúdo é o
  `query-verify.sh`.
- Por padrão NADA é reenviado: o upsert manda `isUpdateText:false` e só os metadados mudam.
  Os modos com texto (`--text-file`/`--text`) existem apenas para quem for tentar trocar o conteúdo — e
  texto existem para reenviar o mesmo conteúdo e para tipos `qa`, e o script avisa e sai 1
  quando a API não substitui o conteúdo.
- Sem `PATCH`, "acrescentar uma etiqueta" = ler a lista atual e regravar a lista completa —
  exatamente o que `add-tag.sh`/`remove-tag.sh` fazem.
- `POST /datasources` é upsert: com `id` existente atualiza o `config`; com `id` inexistente
  cria; sem `id` cria uma fonte nova (para isso use a skill `chatvolt-datastore-add`).
- Limites: payload de 1 MB, 60 requisições/min e 10.000/dia (`402` quando a quota do plano
  acaba). `GET /datasources/{id}` sem `?idstore=` responde 400.

### Trocar o conteúdo de uma fonte existente

O upsert não substitui o texto, então o caminho verificado é apagar e recriar:

1. anote nome, etiquetas e `custom_id` da fonte (`show-source-tags.sh`);
2. apague a fonte (`delete-source.sh` da skill `chatvolt-datastore-add`);
3. recrie com o texto novo reaproveitando os metadados:
   `add-source.sh <api-key> <base> --text-file novo.md --name "<mesmo nome>" --tags a,b --custom-id tenant-x`;
4. confirme o texto novo com uma query de prova (`query-verify.sh`).

### Consulta filtrada

`POST /datastores/{id}/query` com `{ "query", "topK", "filters": { "custom_ids": [...],
"datasource_ids": [...] } }` devolve um **array na raiz** (não `{data:[...]}`), cada trecho com
`text`, `score`, `datasource_name`, `datasource_id`, `custom_id` e `offset`. Com `custom_ids`
válido voltam trechos; com valor inexistente volta `[]` com HTTP 200.

## Scripts auxiliares

Na pasta `scripts/`:

- `list-tags.sh <api-key> <base> [--page-size N]` — agrega as etiquetas de todas as fontes
  (contagem + quais fontes), paginando `/datasources/list`; mostra também as fontes sem etiqueta
- `show-source-tags.sh <api-key> <base> <fonte>` — etiquetas, `custom_id`, status, `nbChunks`,
  `textSize` e `hash` de uma fonte (`CV_JSON=1` devolve o objeto cru da API)
- `set-tags.sh <api-key> <base> <fonte> [--tags a,b | --clear-tags] [--custom-id X |
  --clear-custom-id] [--text-file <f> | --text "<t>"] [--yes]` — grava a lista
  final de etiquetas e/ou o `custom_id`, com antes/depois, confirmação e revalidação. Por padrão
  nada é reenviado (`isUpdateText:false`): só os metadados mudam. `--text-file`/`--text` existem
  apenas para testar troca de conteúdo — a API **ignora** o texto em fonte existente, então o
  script avisa e sai 1 (para trocar conteúdo: apagar a fonte e recriar)
- `add-tag.sh <api-key> <base> <fonte> <etiqueta[,etiqueta]>`
  — acrescenta etiquetas preservando as atuais
- `remove-tag.sh <api-key> <base> <fonte> <etiqueta[,etiqueta]>`
  — remove etiquetas; falha mostrando as atuais se alguma não existir
- `find-by-tag.sh <api-key> <base> <etiqueta[,etiqueta]> [--page-size N]` — lista as fontes que
  têm a(s) etiqueta(s) (filtro local)
- `set-custom-id.sh <api-key> <base> <fonte> <custom-id>|--clear`
  — define/remove o `custom_id` (o filtro que a busca respeita)
- `query-verify.sh <api-key> <base> <query> [--custom-id X] [--datasource-id Y] [--top-k N]
  [--expect-nonempty | --expect-empty]` — mostra os trechos recuperados e, com `--expect-*`,
  vira asserção (sai 1 quando a expectativa falha)

`CV_JSON=1` faz qualquer script imprimir somente JSON em stdout (diagnósticos vão para stderr).
`CV_YES=1` pula as confirmações (uso em script/CI).

## Fluxo típico

```bash
# tudo abaixo a partir da raiz do repo (ou chame os scripts direto em datastore-tags/scripts/)

# o que já existe na base
./chatvolt.sh datastore-tags list-tags.sh "$CHATVOLT_API_KEY" <base>

# marcar três fontes sem tocar no conteúdo já indexado
for f in <fonte1> <fonte2> <fonte3>; do
  ./chatvolt.sh datastore-tags add-tag.sh "$CHATVOLT_API_KEY" <base> "$f" financeiro --yes
done

# segmentar por cliente (é isso que a busca filtra)
./chatvolt.sh datastore-tags set-custom-id.sh "$CHATVOLT_API_KEY" <base> <fonte1> cliente-42 --yes

# provar os dois lados do filtro
./chatvolt.sh datastore-tags query-verify.sh "$CHATVOLT_API_KEY" <base> "prazo de garantia" \
    --custom-id cliente-42 --expect-nonempty
./chatvolt.sh datastore-tags query-verify.sh "$CHATVOLT_API_KEY" <base> "prazo de garantia" \
    --custom-id cliente-99 --expect-empty

# quem são as fontes da etiqueta
./chatvolt.sh datastore-tags find-by-tag.sh "$CHATVOLT_API_KEY" <base> financeiro
```

Se a consulta filtrada voltar vazia com um `custom_id` que você esperava que casasse, o valor
gravado na fonte é a primeira coisa a conferir (`show-source-tags.sh`) — `custom_ids` casa por
igualdade exata e é por fonte, não por etiqueta.
