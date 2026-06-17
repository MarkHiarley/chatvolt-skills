# Chatvolt Skills

Skills para o **pi** (agente de IA) que permitem gerenciar, testar e ajustar agentes **Chatvolt** via API.

## Sobre

| Skill | Descricao |
|-------|-----------|
| **agent-test** | Testa agentes: envia perguntas, mantem conversa, verifica se segue as regras |
| **investigation** | Investiga: busca system prompt, conversas, mensagens e analise de conformidade |
| **prompt-adjust** | Ajusta: edita prompt, troca modelo, altera temperatura |
| **tools-update** | Gerencia tools: cria, lista, atualiza e deleta (datastore, HTTP, form) |

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
```

Ou use o instalador automatico:

```bash
./install.sh
```

##### Opcao B — Copiar as pastas

```bash
mkdir -p ~/.pi/agent/skills
cp -r agent-test investigation prompt-adjust tools-update ~/.pi/agent/skills/
```

```bash
./install.sh --copy
```

##### Opcao C — Usar direto com --skill (sem instalar)

```bash
pi --skill ./agent-test
pi --skill ./investigation
pi --skill ./agent-test --skill ./tools-update
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
```

> Se der erro de permissao, abra o PowerShell como **Administrador** ou use a Opcao B.

##### Opcao B — Copiar as pastas

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.pi\agent\skills"
Copy-Item -Recurse -Force "$pwd\agent-test" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\investigation" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\prompt-adjust" "$env:USERPROFILE\.pi\agent\skills\"
Copy-Item -Recurse -Force "$pwd\tools-update" "$env:USERPROFILE\.pi\agent\skills\"
```

##### Opcao C — Usar direto com --skill (sem instalar)

```powershell
pi --skill .\agent-test
pi --skill .\investigation
pi --skill .\agent-test --skill .\tools-update
```

---

### 3. Como usar com o pi

Apos instalado, converse com o pi. As skills carregam automaticamente quando o contexto faz sentido. Exemplos:

#### Testar um agente
> "pi, testa o agente [ID] com API key [KEY]. Quero ver se ele responde em portugues e nao inventa precos."

#### Investigar um agente
> "pi, investiga o agente [ID]. Quero ver o system prompt e as tools que ele tem."

#### Ajustar prompt ou modelo
> "pi, troca o modelo do agente [ID] para gpt_4_o e ajusta a temperatura pra 0.2."

#### Gerenciar tools
> "pi, lista as tools do agente [ID]."
> "pi, cria uma HTTP tool no agente [ID] pra consultar precos."

### 4. Forcar o carregamento de uma skill

```
/skill:chatvolt-agent-test
/skill:chatvolt-investigation
/skill:chatvolt-prompt-adjust
/skill:chatvolt-tools-update
```

### 5. Variaveis de ambiente (atalho)

#### Linux / macOS (no ~/.bashrc ou ~/.zshrc)
```bash
export CHATVOLT_API_KEY="sk-..."
export CHATVOLT_AGENT_ID="cminahdll02m496hey09nozu8"
```

#### Windows (PowerShell, no $PROFILE)
```powershell
$env:CHATVOLT_API_KEY = "sk-..."
$env:CHATVOLT_AGENT_ID = "cminahdll02m496hey09nozu8"
```

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
```

---

## Exemplos de conversas com o pi

### Exemplo 1: Testar se o agente segue o prompt

```
Voce: pi, testa o agente cminahdll02m496hey09nozu8
      com a API key sk-1234
      Quero testar se ele responde em portugues e se apresenta como "Assistente"

  pi: Buscando configuracao do agente...

      Agent: Meu Agente (gpt_4_o, temp: 0.3)

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
Voce: pi, adiciona uma tool HTTP no agente cminahdll02m496hey09nozu8
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
| `GET` | `/agents/{id}` | investigation, prompt-adjust, agent-test |
| `PATCH` | `/agents/{id}` | prompt-adjust |
| `POST` | `/agents/{id}/query` | investigation, agent-test |
| `GET` | `/api/agents/{id}/tools` | tools-update |
| `POST` | `/api/agents/{id}/tools` | tools-update |
| `PATCH` | `/api/agents/{id}/tools/{toolId}` | tools-update |
| `DELETE` | `/api/agents/{id}/tools/{toolId}` | tools-update |
| `GET` | `/conversation?agentId={id}` | investigation |
| `GET` | `/conversation/{id}/messages/{count}` | investigation |

**Base URL:** `https://api.chatvolt.ai`
**Autenticacao:** `Authorization: Bearer <api-key>`

---

## Estrutura do repositorio

```
chatvolt-skills/
├── README.md
├── install.sh                   -- Instalador automatico (Linux/macOS)
├── chatvolt.sh                  -- Script de atalho (uso direto)
├── agent-test/                  -- Skill de teste de agentes
│   ├── SKILL.md
│   └── scripts/
│       ├── get-agent.sh
│       ├── send-query.sh
│       ├── analyze-results.sh
│       └── test-agent.sh
├── investigation/               -- Skill de investigacao
│   ├── SKILL.md
│   └── scripts/
├── prompt-adjust/               -- Skill de ajuste de prompt
│   ├── SKILL.md
│   └── scripts/
└── tools-update/                -- Skill de gerenciamento de tools
    ├── SKILL.md
    └── scripts/
```

---

> A maneira mais facil de usar e simplesmente conversar com o pi. Ele ja tem as skills carregadas e sabe o que fazer. Basta pedir.
