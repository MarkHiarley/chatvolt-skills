# Chatvolt Skills

Skills para o **pi** (agente de IA) que permitem gerenciar, testar e ajustar agentes **Chatvolt** via API.

## Sobre

| Skill | Descricao |
|-------|-----------|
| **agent-test** | Testa agentes: envia perguntas, mantem conversa, verifica se segue as regras |
| **investigation** | Investiga: busca system prompt, conversas, mensagens e analise de conformidade |
| **prompt-adjust** | Ajusta: edita prompt, troca modelo, altera temperatura |
| **tools-update** | Gerencia tools: cria, lista, atualiza e deleta (datastore, HTTP, form) |
| **conversation-cleanup** | Lista e deleta conversas de teste (canal `api`) |
| **datastore-add** | Cria base de conhecimento, adiciona fontes (texto/QA/URL), confere indexação e conecta a base ao agente |
| **datastore-tags** | Etiqueta fontes da base (`config.tags`) e define `custom_id` para filtro multi-tenant |
| **api-call** | Chama qualquer endpoint da API (136 operações) e lista o catálogo de rotas disponíveis |
| **contacts** | Gerencia contatos e variáveis de contato |
| **conversation-actions** | Ações de atendimento: assign, status, prioridade, IA, notas, tags, variáveis, envio, export |
| **agent-admin** | Cria/lista/deleta agentes, gera o prompt por IA, checa handle livre, lista templates, whitelist e envio de formulário ao agente |
| **artifacts** | Catálogo de artefatos, categorias, mídia (upload) e busca |
| **crm** | Cenários, etapas, logs de conversa e eventos em tempo real (SSE) |
| **dispatches** | Disparos em massa, listas de contatos e fila de envio |
| **whatsapp** | Templates e mensagens interativas do WhatsApp (botões, listas, CTA, localização) |
| **integrations** | Envio por Twilio, Z-API e Zapper |
| **tags** | Tags da organização (indisponível neste plano: as rotas respondem 404) |
| **mercadolivre** | Produtos sincronizados do Mercado Livre |

> **Atualizações:** toda skill roda `scripts/check-updates.sh` ao ser carregada (Passo 0 no
> `SKILL.md`). Ela avisa quando a doc OpenAPI (docs.chatvolt.ai), as operações da fonte da doc
> ou o código-fonte `appchatvolt_dev` mudaram. Desligue com `CV_UPDATE_CHECK=0`; aponte o clone
> com `CV_SRC=/caminho/do/appchatvolt_dev`. Detalhes em [SOURCES.md](SOURCES.md), seção 8.

---

## Tutorial rapido

### 1. Pre-requisitos

- **pi** instalado (veja abaixo como instalar)
- **Chave de API do Chatvolt**: https://app.chatvolt.ai/settings/api-keys
- **ID do agente** (UUID ou handle como `@meu-agente`)

#### Como instalar o pi

> **pi** e um agente de IA de codigo aberto para terminal.

| Sistema | Instalacao |
|---------|-----------|
| Linux / macOS / WSL | `npm install -g @earendil-works/pi-coding-agent` |
| Windows (PowerShell) | `npm install -g @earendil-works/pi-coding-agent` |
| Alternativa (pip) | `pip install pi-ai` |
| Site oficial | https://pi.dev |
| Documentacao | https://github.com/earendil-works/pi |
| Pacote npm | https://www.npmjs.com/package/@earendil-works/pi-coding-agent |

> Necessario **Node.js 18+**. Baixe em https://nodejs.org

Apos instalar, teste com:

```bash
pi --version
```

### 2. Instalacao das skills

Clone o repositorio:

```bash
git clone https://github.com/MarkHiarley/chatvolt-skills.git
cd chatvolt-skills
```

Execute o instalador:

```bash
./install.sh
```

> O `install.sh` cria links simbolicos das skills no `~/.pi/agent/skills/`.
> Use `./install.sh --copy` se preferir copiar as pastas em vez de link.

Se preferir instalar manualmente, escolha seu sistema:

---

#### Linux / macOS

##### Opcao A — Link simbolico (recomendado)

```bash
mkdir -p ~/.pi/agent/skills
ln -s "$(pwd)/agent-test" ~/.pi/agent/skills/
ln -s "$(pwd)/investigation" ~/.pi/agent/skills/
ln -s "$(pwd)/prompt-adjust" ~/.pi/agent/skills/
ln -s "$(pwd)/tools-update" ~/.pi/agent/skills/
ln -s "$(pwd)/conversation-cleanup" ~/.pi/agent/skills/
ln -s "$(pwd)/datastore-add" ~/.pi/agent/skills/
ln -s "$(pwd)/datastore-tags" ~/.pi/agent/skills/
ln -s "$(pwd)/api-call" ~/.pi/agent/skills/
ln -s "$(pwd)/contacts" ~/.pi/agent/skills/
ln -s "$(pwd)/conversation-actions" ~/.pi/agent/skills/
ln -s "$(pwd)/agent-admin" ~/.pi/agent/skills/
ln -s "$(pwd)/artifacts" ~/.pi/agent/skills/
ln -s "$(pwd)/crm" ~/.pi/agent/skills/
ln -s "$(pwd)/dispatches" ~/.pi/agent/skills/
ln -s "$(pwd)/whatsapp" ~/.pi/agent/skills/
ln -s "$(pwd)/integrations" ~/.pi/agent/skills/
ln -s "$(pwd)/tags" ~/.pi/agent/skills/
ln -s "$(pwd)/mercadolivre" ~/.pi/agent/skills/
```

Ou use o instalador automatico:

```bash
./install.sh
```

##### Opcao B — Copiar as pastas

```bash
mkdir -p ~/.pi/agent/skills
cp -r agent-test investigation prompt-adjust tools-update conversation-cleanup datastore-add datastore-tags api-call contacts conversation-actions agent-admin artifacts crm dispatches whatsapp integrations tags mercadolivre ~/.pi/agent/skills/
```

```bash
./install.sh --copy
```

##### Opcao C — Usar direto com --skill (sem instalar)

```bash
pi --skill ./agent-test
pi --skill ./investigation
pi --skill ./agent-test --skill ./tools-update
pi --skill ./datastore-add --skill ./datastore-tags
pi --skill ./api-call --skill ./crm
```

---

#### Windows (PowerShell)

##### Opcao A — Link simbolico (recomendado)

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.pi\agent\skills"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\agent-test" -Target "$pwd\agent-test"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\investigation" -Target "$pwd\investigation"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\prompt-adjust" -Target "$pwd\prompt-adjust"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\tools-update" -Target "$pwd\tools-update"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\conversation-cleanup" -Target "$pwd\conversation-cleanup"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\datastore-add" -Target "$pwd\datastore-add"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\datastore-tags" -Target "$pwd\datastore-tags"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\api-call" -Target "$pwd\api-call"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\contacts" -Target "$pwd\contacts"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\conversation-actions" -Target "$pwd\conversation-actions"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\agent-admin" -Target "$pwd\agent-admin"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\artifacts" -Target "$pwd\artifacts"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\crm" -Target "$pwd\crm"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\dispatches" -Target "$pwd\dispatches"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\whatsapp" -Target "$pwd\whatsapp"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\integrations" -Target "$pwd\integrations"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\tags" -Target "$pwd\tags"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.pi\agent\skills\mercadolivre" -Target "$pwd\mercadolivre"
```

> Se der erro de permissao, abra o PowerShell como **Administrador** ou use a Opcao B.

##### Opcao B — Copiar as pastas

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.pi\agent\skills"
Copy-Item -Recurse -Force "$pwd\agent-test" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\investigation" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\prompt-adjust" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\tools-update" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\conversation-cleanup" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\datastore-add" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\datastore-tags" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\api-call" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\contacts" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\conversation-actions" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\agent-admin" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\artifacts" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\crm" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\dispatches" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\whatsapp" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\integrations" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\tags" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\mercadolivre" "$env:USERPROFILE\.pi\agent\skills\"
```

##### Opcao C — Usar direto com --skill (sem instalar)

```powershell
pi --skill .\agent-test
pi --skill .\investigation
pi --skill .\agent-test --skill .\tools-update
pi --skill .\datastore-add --skill .\datastore-tags
pi --skill .\api-call --skill .\crm
```

---

### 3. Como usar com o pi

Apos instalado, converse com o pi. As skills carregam automaticamente quando o contexto faz sentido. Exemplos:

#### Testar um agente
> "pi, testa o agente [ID] com API key [KEY]. Quero ver se ele responde em portugues e nao inventa precos."

#### Investigar um agente
> "pi, investiga o agente [ID]. Quero ver o system prompt e as tools que ele tem."

#### Ajustar prompt ou modelo
> "pi, troca o modelo do agente [ID] para gpt_54_nano e ajusta a temperatura pra 0.2."
> (a lista de modelos válidos é sempre buscada ao vivo em `GET /agents/models`)

#### Gerenciar tools
> "pi, lista as tools do agente [ID]."
> "pi, cria uma HTTP tool no agente [ID] pra consultar precos."

#### Alimentar uma base de conhecimento
> "pi, cria uma base chamada Politica de Trocas e adiciona o arquivo politica.md com as etiquetas faq, pos-venda."
> "pi, confere se a fonte indexou e roda uma query de prova na base [ID]."

#### Etiquetar fontes da base
> "pi, quais etiquetas existem na base [ID]?"
> "pi, adiciona a etiqueta devolucao na fonte [ID] e marca custom_id tenant-1."

### 4. Forcar o carregamento de uma skill

```
/skill:chatvolt-agent-test
/skill:chatvolt-investigation
/skill:chatvolt-prompt-adjust
/skill:chatvolt-tools-update
/skill:chatvolt-conversation-cleanup
/skill:chatvolt-datastore-add
/skill:chatvolt-datastore-tags
/skill:chatvolt-api-call
/skill:chatvolt-contacts
/skill:chatvolt-conversation-actions
/skill:chatvolt-agent-admin
/skill:chatvolt-artifacts
/skill:chatvolt-crm
/skill:chatvolt-dispatches
/skill:chatvolt-whatsapp
/skill:chatvolt-integrations
/skill:chatvolt-tags
/skill:chatvolt-mercadolivre
```

### 5. Variaveis de ambiente (atalho)

#### Linux / macOS (no ~/.bashrc ou ~/.zshrc)
```bash
export CHATVOLT_API_KEY="sk-..."
export CHATVOLT_AGENT_ID="seu-agent-id"
```

#### Windows (PowerShell, no $PROFILE)
```powershell
$env:CHATVOLT_API_KEY = "sk-..."
$env:CHATVOLT_AGENT_ID = "seu-agent-id"
```

---

## Instalar em outras ferramentas (Claude, Codex, Gemini)

As skills são pastas com um `SKILL.md`, no formato do padrão aberto Agent Skills. Por isso
funcionam em várias ferramentas, desde que cada uma leia a pasta do lugar certo. A tabela
resume onde cada ferramenta procura as skills. Os caminhos vêm da documentação oficial de cada
ferramenta, pesquisada em 2026-10-30.

| Ferramenta | Versão | Onde instalar | Como usar |
|---|---|---|---|
| Claude Code (CLI, extensão de IDE) | local | `~/.claude/skills/` (global) ou `.claude/skills/` (projeto) | automática, ou `/nome-da-skill` |
| Claude Desktop | desktop | Customize > Skills > Add > Upload skill (zip de cada pasta) | automática |
| Claude.ai | web | Settings > Capabilities > Skills (zip de cada pasta), com code execution ligado | automática |
| Codex (CLI, extensão de IDE, app desktop) | local | `~/.agents/skills/` (global) ou `.agents/skills/` (projeto) | `$nome-da-skill` ou `/skills` |
| Gemini CLI | local | `~/.gemini/skills/` ou `~/.agents/skills/` | `/skills list` no chat |
| Gemini (app e gemini.google.com) | web / desktop / mobile | Skills na barra lateral: upload de pasta com `SKILL.md` | automática |

> **Antes de começar:** as skills chamam scripts `bash` que usam `curl` e `python3`. Defina a chave
> com `export CHATVOLT_API_KEY=...` (ou passe como primeiro argumento). No Windows, use Git Bash
> ou WSL para os scripts. Nos links com symlink, a checagem de atualizações (Passo 0) continua
> funcionando, porque segue o link até o repo.

### Claude Code

Claude Code lê a pasta global `~/.claude/skills/`. Para ter as skills em todos os projetos,
crie links simbólicos para cada pasta:

```bash
REPO=/caminho/para/chatvolt-skills
DEST=~/.claude/skills
mkdir -p "$DEST"
for s in agent-test investigation prompt-adjust tools-update conversation-cleanup datastore-add datastore-tags api-call contacts conversation-actions agent-admin artifacts crm dispatches whatsapp integrations tags mercadolivre; do ln -sfn "$REPO/$s" "$DEST/$s"; done
```

Reinicie o Claude Code. Para atualizar as skills, faça `git pull` no repo: o link já aponta para
a versão nova.

### Claude Desktop e Claude.ai (web)

Nessas versões, cada skill é enviada como um arquivo zip. Gere um zip por pasta:

```bash
REPO=/caminho/para/chatvolt-skills
OUT=~/chatvolt-skills-zips
mkdir -p "$OUT"
for s in agent-test investigation prompt-adjust tools-update conversation-cleanup datastore-add datastore-tags api-call contacts conversation-actions agent-admin artifacts crm dispatches whatsapp integrations tags mercadolivre; do (cd "$REPO" && python3 -m zipfile -c "$OUT/$s.zip" "$s"); done
```

- **Claude Desktop**: abra Customize > Skills, selecione Add e depois Upload skill. Envie um zip por vez.
- **Claude.ai**: ative code execution em Settings > Capabilities e depois envie os zips em Settings > Capabilities > Skills. O plano precisa incluir skills (Pro, Max, Team ou Enterprise).

**Limitação:** as skills rodam no sandbox da Claude, e não confirmei se esse sandbox alcança
`api.chatvolt.ai` e `chat-volt.mintlify.app`. Teste primeiro com uma operação sem efeito, como
`check-handle.sh` ou `list-agents.sh`.

### Codex (CLI, extensão de IDE e app desktop)

O Codex lê `~/.agents/skills/` (global) e `.agents/skills/` (dentro do repo). Também lê o caminho
antigo `~/.codex/skills/`:

```bash
REPO=/caminho/para/chatvolt-skills
DEST=~/.agents/skills
mkdir -p "$DEST"
for s in agent-test investigation prompt-adjust tools-update conversation-cleanup datastore-add datastore-tags api-call contacts conversation-actions agent-admin artifacts crm dispatches whatsapp integrations tags mercadolivre; do ln -sfn "$REPO/$s" "$DEST/$s"; done
```

Para usar, digite `$` e o nome da skill, ou `/skills` para escolher da lista.

Não encontrei documentação oficial de skills para o Codex na versão web (cloud). A doc oficial
cita a CLI, a extensão de IDE e o app desktop.

### Gemini CLI

O Gemini CLI lê `~/.gemini/skills/` e `~/.agents/skills/` (globais), e `.gemini/skills/` (projeto).
A forma mais segura é o link simbólico, igual aos outros:

```bash
REPO=/caminho/para/chatvolt-skills
DEST=~/.gemini/skills
mkdir -p "$DEST"
for s in agent-test investigation prompt-adjust tools-update conversation-cleanup datastore-add datastore-tags api-call contacts conversation-actions agent-admin artifacts crm dispatches whatsapp integrations tags mercadolivre; do ln -sfn "$REPO/$s" "$DEST/$s"; done
```

No chat, `/skills list` mostra as skills encontradas. Existe também o comando
`gemini skills install <fonte>`, mas não confirmei quais fontes ele aceita além de URLs.

### Gemini (app e gemini.google.com)

Em Skills, no app ou no site, dá para criar uma skill ou enviar uma pasta com `SKILL.md`. Segundo
a ajuda do Google, a função está disponível no app mobile, no app Mac e em gemini.google.com.

**Limitação:** a ajuda do Google não fala em executar scripts. Sem um shell local, os scripts das
skills não rodam. Nesse caso, a skill funciona só como instruções. Para o fluxo completo, use o
Gemini CLI.

### Links da documentação oficial

- Claude Code: <https://code.claude.com/docs/en/skills>
- Claude (web): <https://support.claude.com/en/articles/12512180-use-skills-in-claude>
- Codex: <https://learn.chatgpt.com/docs/build-skills>
- Gemini CLI: <https://geminicli.com/docs/cli/skills/>
- Gemini (app): <https://support.google.com/gemini/answer/17094296>

## Conectando o pi com OpenCode

O **opencode-pi** registra o OpenCode como provedor no pi. Você escolhe o modelo via `/model` e autentica via `/login`.

### 1. Instalar a extensão

```bash
pi install npm:opencode-pi
```

Depois rode `/reload` no pi (ou reinicie).

Verifique:
```bash
pi list
```

### 2. Autenticar (via pi, uma vez)

Dentro do pi, rode:

```
/login
```

Selecione **OpenCode** como provedor. Pegue sua chave em https://opencode.ai/auth e cole quando o pi pedir.

> Modelos gratuitos como `deepseek-v4-flash-free` também precisam desse login.

### 3. Escolher o modelo

Ainda dentro do pi:

```
/model
```

Escolha `opencode/deepseek-v4-flash-free` (ou outro modelo disponível).

Também dá pra iniciar direto:
```bash
pi --provider opencode-cli --model opencode/deepseek-v4-flash-free
```

### 4. Comandos úteis

```
/opencode-pi status    → status da extensão
/opencode-pi models    → lista modelos disponíveis
/opencode-pi update    → atualiza lista de modelos (o roster muda com frequência)
/opencode-pi help      → ajuda
```

### 5. Outros modelos gratuitos

- `opencode/deepseek-v4-flash-free`
- `opencode/mimo-v2.5-free`
- `opencode/nemotron-3-super-free`
- `opencode/big-pickle`

> Extensão: https://pi.dev/packages/opencode-pi
> Chave de API: https://opencode.ai/auth

---

## Uso direto pelo terminal (sem o pi)

Cada skill tem scripts independentes em `scripts/`. Funcionam em qualquer sistema com `bash` e `curl` (no Windows use Git Bash ou WSL).

```bash
# Ver configuracao
./agent-test/scripts/get-agent.sh "$API_KEY" "$AGENT_ID"

# Testar interativamente
./agent-test/scripts/test-agent.sh "$API_KEY" "$AGENT_ID"

# Listar tools
./tools-update/scripts/list-tools.sh "$API_KEY" "$AGENT_ID"

# Listar modelos disponiveis (publico, sem chave)
./prompt-adjust/scripts/list-models.sh "$API_KEY"

# Bases de conhecimento
./datastore-add/scripts/list-datastores.sh "$API_KEY"
./datastore-add/scripts/add-source.sh "$API_KEY" "$DATASTORE_ID" --text-file politica.md --tags faq,pos-venda
./datastore-add/scripts/query-base.sh "$API_KEY" "$DATASTORE_ID" "qual o prazo de troca?"

# Etiquetas das fontes
./datastore-tags/scripts/list-tags.sh "$API_KEY" "$DATASTORE_ID"
./datastore-tags/scripts/add-tag.sh "$API_KEY" "$DATASTORE_ID" "$SOURCE_ID" devolucao --text-file politica.md
```

Todos os scripts aceitam `CV_JSON=1` (saída só JSON em stdout, diagnósticos em stderr) — útil para encadear com `jq`/outros agentes.

---

## Exemplos de conversas com o pi

### Exemplo 1: Testar se o agente segue o prompt

```
Voce: pi, testa o agente seu-agent-id
      com a API key sk-1234
      Quero testar se ele responde em portugues e se apresenta como "Assistente"

  pi: Buscando configuracao do agente...

      Agent: Meu Agente (gpt_54_nano, temp: 0.3)

      System Prompt:
      """Voce e um assistente da Empresa X.
      Regras:
      - Responda sempre em portugues
      - Se apresente como "Assistente da Empresa X"
      - Nao fornea precos, direcione para o site"""

      Qual o fluxo esperado? O que o agente DEVE fazer?

Voce: Responder em portugues, se apresentar como
      "Assistente da Empresa X", nao inventar precos

  pi: Ok. Iniciando nova conversa.
      Qual a primeira pergunta?

Voce: Quem e voce?

  pi: Enviando...

      Assistant: Ola! Eu sou o Assistente da Empresa X.
      Como posso ajudar voce hoje?

      Regras verificadas:
      - Respondeu em portugues: OK
      - Se apresentou corretamente: OK
```

### Exemplo 2: Adicionar uma tool HTTP

```
Voce: pi, adiciona uma tool HTTP no agente seu-agent-id
      para consultar clima

  pi: Qual a URL da API?

Voce: https://api.weather.com/v1/weather

  pi: Qual o metodo HTTP?

Voce: GET

  pi: Precisa de headers?

Voce: sim, Authorization: Bearer token123

  pi: Tem parametros de query?

Voce: sim, city (obrigatorio, preenchido pelo usuario)

  pi: Tool criada com sucesso.
      ID: clwscf12b000208l6e4f3h7j8
      Name: Consultar Clima
      URL: https://api.weather.com/v1/weather
```

---

## API

| Metodo | Endpoint | Skill |
|--------|----------|-------|
| `GET` | `/agents` | agent-test, investigation |
| `GET` | `/agents/{id}` | agent-test, investigation, prompt-adjust |
| `PATCH` | `/agents/{id}` | prompt-adjust |
| `GET` | `/agents/models` | prompt-adjust |
| `POST` | `/agents/{id}/query` | agent-test, investigation, prompt-adjust |
| `PATCH` | `/agents/{id}/webhook?type=&enabled=` | prompt-adjust |
| `GET` | `/agents/{id}/tools` | agent-test, tools-update |
| `POST` | `/agents/{id}/tools` | tools-update, datastore-add |
| `PATCH` | `/agents/{id}/tools/{toolId}` | tools-update |
| `DELETE` | `/agents/{id}/tools/{toolId}` | tools-update |
| `GET` | `/conversation` | investigation, conversation-cleanup |
| `GET` | `/conversation/{id}` | conversation-cleanup |
| `DELETE` | `/conversation/{id}` | conversation-cleanup |
| `GET` | `/conversation/{id}/messages/{count}` | investigation, agent-test |
| `GET` | `/datastores/list` | datastore-add |
| `POST` | `/datastores` | datastore-add |
| `GET` | `/datastores/{id}` | datastore-add |
| `PATCH` | `/datastores/{id}` | datastore-add |
| `DELETE` | `/datastores/{id}` | datastore-add |
| `POST` | `/datastores/{id}/query` | datastore-add, datastore-tags |
| `GET` | `/datasources/list?datastoreId={id}` | datastore-add, datastore-tags |
| `POST` | `/datasources` | datastore-add, datastore-tags |
| `GET` | `/datasources/{id}?idstore={datastoreId}` | datastore-add, datastore-tags |
| `DELETE` | `/datasources/{id}` | datastore-add |

**Base URL:** `https://api.chatvolt.ai`
**Autenticacao:** `Authorization: Bearer <api-key>`

Detalhes de contrato (formato real das respostas, parametros, divergencias da documentacao oficial e limites de rate limit) estao em [`SOURCES.md`](SOURCES.md). Pontos que mais confundem:

- Nao existe `GET /agents/{id}/tools/{toolId}` (responde `404`) — para ver uma tool, filtre a listagem.
- `POST /agents/{id}/webhook` **nao existe**: o endpoint e um toggle via `PATCH` com `?type=&enabled=`.
- A maioria das rotas devolve o objeto/array na raiz; so `/datastores/list` e `/datasources/list` usam envelope `{data, pagination}`.
- `GET /conversation` filtra por `agentId`, `channel`, `createdAt`, `endDate`, `status`, `priority`, `tag`, `ai`, `limit` (max 100) e `cursor` — **nao** por `organizationId`.

---

## Estrutura do repositorio

```
chatvolt-skills/
├── README.md
├── SOURCES.md                   -- Contrato real da API (doc x openapi x probe ao vivo)
├── install.sh                   -- Instalador automatico (Linux/macOS)
├── chatvolt.sh                  -- Script de atalho (uso direto)
├── tests/
│   ├── smoke.sh                 -- Suite headless (--lint, --stub, --live, --probe)
│   ├── stub_server.py           -- Stub HTTP offline da API
│   └── stub-fixtures/           -- Rotas e casos de teste por skill
├── agent-test/                  -- Teste de agentes (config, query, fluxo esperado)
├── investigation/               -- Investigacao (config, conversas, mensagens)
├── prompt-adjust/               -- Prompt, modelo, temperatura e webhook
├── tools-update/                -- Tools do agente (http, datastore, form, ...)
├── conversation-cleanup/        -- Conversas de teste (canal api)
├── datastore-add/               -- Base de conhecimento (criar, alimentar, consultar)
├── datastore-tags/              -- Etiquetas e custom_id das fontes da base
├── api-call/                    -- Chamada generica + catalogo das 136 rotas
├── contacts/                    -- Contatos e variaveis de contato
├── conversation-actions/        -- Assign, status, prioridade, IA, notas, tags, envio, export
├── agent-admin/                 -- Criar/remover agente, whitelist, formulario ao agente
├── artifacts/                   -- Artefatos, categorias, midia e busca
├── crm/                         -- Cenarios, etapas, logs e eventos (SSE)
├── dispatches/                  -- Disparos, listas de contatos e fila
├── whatsapp/                    -- Templates e mensagens interativas
├── integrations/                -- Twilio, Z-API e Zapper
├── tags/                        -- Tags da organizacao (404 neste plano)
└── mercadolivre/                -- Produtos sincronizados do Mercado Livre

Cada skill segue o mesmo formato:
    <skill>/SKILL.md             -- Instrucoes para o agente
    <skill>/scripts/<nome>.sh    -- Scripts independentes
    <skill>/scripts/_lib.sh      -- Helpers HTTP (identico em todas as skills)
    tests/stub-fixtures/<skill>.json -- Rotas simuladas + casos de teste da skill
```

---

## Documentacao e testes

A documentacao oficial fica em <https://chat-volt.mintlify.app/pages/agents/reference> (indice completo em <https://chat-volt.mintlify.site/llms.txt>). Ela tem divergencias conhecidas em relacao ao comportamento real da API — todas catalogadas em [`SOURCES.md`](SOURCES.md), que e a fonte da verdade deste repositorio.

```bash
# Verificacao estatica (sintaxe, _lib.sh identico, padroes proibidos)
./tests/smoke.sh --lint

# Execucao offline contra o stub (sem tocar a API real)
./tests/smoke.sh --stub

# Leituras reais (exige chave)
CHATVOLT_API_KEY="sk-..." CHATVOLT_AGENT_ID="seu-agent-id" ./tests/smoke.sh --live

# Inclui escrita em recursos descartaveis (cria e apaga agente/base OMP-SMOKE-*)
CHATVOLT_API_KEY="sk-..." ./tests/smoke.sh --live --mutating
```

---

> A maneira mais facil de usar e simplesmente conversar com o pi. Ele ja tem as skills carregadas e sabe o que fazer. Basta pedir.
