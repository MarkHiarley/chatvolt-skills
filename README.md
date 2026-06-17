# Chatvolt Skills 🎯

Skills para o **pi** (agente de IA) que permitem gerenciar, testar e ajustar agentes **Chatvolt** via API.

## 📋 O que essas skills fazem

| Skill | O que faz |
|-------|-----------|
| **agent-test** | Testa agentes: envia perguntas, mantém conversa, verifica se segue as regras |
| **investigation** | Investiga: busca system prompt, conversas, mensagens e analisa conformidade |
| **prompt-adjust** | Ajusta: edita prompt, troca modelo, altera temperatura |
| **tools-update** | Gerencia tools: cria, lista, atualiza e deleta (datastore, HTTP, form) |

---

## 🚀 Tutorial rápido

### 1. Pré-requisitos

- **pi** instalado (https://pi.ai)
- **Chave de API do Chatvolt** → https://app.chatvolt.ai/settings/api-keys
- **ID do agente** que você quer gerenciar (UUID ou handle tipo `@meu-agente`)

### 2. Instalação — você NÃO precisa clonar este repositório

As skills já estão instaladas automaticamente no pi em:
```
~/.pi/agent/skills/
```

O pi já detecta todas as skills e carrega conforme a necessidade.

> Este repositório no GitHub serve como **fonte oficial** e **documentação**.  
> Você só precisa clonar SE quiser ver os scripts ou contribuir:
> ```bash
> git clone https://github.com/MarkHiarley/chatvolt-skills.git
> cd chatvolt-skills
> ```

### 3. Como usar com o pi

Basta **conversar** com o pi. As skills carregam automaticamente quando o contexto faz sentido. Exemplos:

#### 🧪 Testar um agente
> "pi, testa o agente [ID] com API key [KEY]. Quero ver se ele responde em português e não inventa preços."
>
> *O pi pergunta qual o fluxo esperado, inicia uma conversa e vai te guiando.*

#### 🔍 Investigar um agente
> "pi, investiga o agente [ID]. Quero ver o system prompt e as tools que ele tem."
>
> *O pi busca a configuração completa e exibe.*

#### ✏️ Ajustar prompt ou modelo
> "pi, troca o modelo do agente [ID] para gpt_4_o e ajusta a temperatura pra 0.2."
>
> *O pi aplica as alterações via API.*

#### 🛠️ Gerenciar tools
> "pi, lista as tools do agente [ID]."
>
> *O pi mostra todas as tools configuradas.*

> "pi, cria uma HTTP tool no agente [ID] pra consultar preços."
>
> *Opi pergunta a URL, método, headers e configura.*

### 4. Forçar o carregamento de uma skill

Se quiser chamar uma skill específica pelo nome:

```
/skill:chatvolt-agent-test
/skill:chatvolt-investigation
/skill:chatvolt-prompt-adjust
/skill:chatvolt-tools-update
```

### 5. Variáveis de ambiente (atalho)

Para não digitar a chave toda vez, defina no `~/.bashrc` ou `~/.zshrc`:

```bash
export CHATVOLT_API_KEY="sk-..."
export CHATVOLT_AGENT_ID="cminahdll02m496hey09nozu8"
```

Depois é só chamar o pi e falar:
> "pi, testa o agente padrão com a query 'Qual o horário de funcionamento?'"

---

## 💻 Usando direto pelo terminal (sem o pi)

Cada skill tem scripts independentes em `scripts/`:

```bash
# Ver configuração
~/.pi/agent/skills/chatvolt-agent-test/scripts/get-agent.sh "$CHATVOLT_API_KEY" "$CHATVOLT_AGENT_ID"

# Testar interativamente
~/.pi/agent/skills/chatvolt-agent-test/scripts/test-agent.sh "$CHATVOLT_API_KEY" "$CHATVOLT_AGENT_ID"

# Listar tools
~/.pi/agent/skills/chatvolt-tools-update/scripts/list-tools.sh "$CHATVOLT_API_KEY" "$CHATVOLT_AGENT_ID"
```

---

## 📖 Exemplos de conversas com o pi

### Exemplo 1: Testar se o agente segue o prompt

```
Você: pi, testa o agente cminahdll02m496hey09nozu8
      com a API key sk-1234
      Quero testar se ele responde em português e se apresenta como "Assistente"

  pi: Beleza! Deixa eu buscar a configuração do agente...
      
      Agent: Meu Agente (gpt_4_o, temp: 0.3)
      
      System Prompt:
      """Você é um assistente da Empresa X.
      Regras:
      - Responda sempre em português
      - Se apresente como "Assistente da Empresa X"
      - Não forneça preços, direcione para o site"""
      
      Qual o fluxo esperado? O que o agente DEVE fazer?
      
Você: Responder em português, se apresentar como
      "Assistente da Empresa X", não inventar preços

  pi: Ok! Vou iniciar uma nova conversa. 
      Qual a primeira pergunta que você quer enviar?
      
Você: Quem é você?

  pi: Enviando...
      
      Assistant: Olá! Eu sou o Assistente da Empresa X. 
      Como posso ajudar você hoje?
      
      ✅ Respondeu em português
      ✅ Se apresentou corretamente
      
      Quer continuar o teste? (sim/nova conversa/analisar/sair)
```

### Exemplo 2: Adicionar uma tool HTTP

```
Você: pi, adiciona uma tool HTTP no agente cminahdll02m496hey09nozu8
      pra consultar clima

  pi: Qual a URL da API?
      
Você: https://api.weather.com/v1/weather

  pi: Qual o método HTTP?
      
Você: GET

  pi: Precisa de headers? (ex: Authorization)
      
Você: sim, Authorization: Bearer token123

  pi: Tem parâmetros de query?
      
Você: sim, city (obrigatório, preenchido pelo usuário)

  pi: ✅ Tool criada com sucesso!
      ID: clwscf12b000208l6e4f3h7j8
      Name: Consultar Clima
      URL: https://api.weather.com/v1/weather
```

---

## 🔌 API usada

| Método | Endpoint | Skill |
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
**Autenticação:** `Authorization: Bearer <api-key>`

---

## 📁 Estrutura do repositório

```
chatvolt-skills/
├── README.md                    ← Você está aqui
├── chatvolt.sh                  ← Script de atalho (uso direto)
├── agent-test/                  ← Skill de teste de agentes
│   ├── SKILL.md                 ← Instruções pro pi
│   └── scripts/                 ← Scripts auxiliares
│       ├── get-agent.sh
│       ├── send-query.sh
│       ├── analyze-results.sh
│       └── test-agent.sh
├── investigation/               ← Skill de investigação
│   ├── SKILL.md
│   └── scripts/
├── prompt-adjust/               ← Skill de ajuste de prompt
│   ├── SKILL.md
│   └── scripts/
└── tools-update/                ← Skill de gerenciamento de tools
    ├── SKILL.md
    └── scripts/
```

---

> 💡 **Dica:** A maneira mais fácil de usar é simplesmente conversar com o pi.  
> Ele já tem as skills carregadas e sabe o que fazer. Basta pedir!
