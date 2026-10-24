# Hands-on Kiro — o agente que constrói o agente (40 min)

Você vai usar o Kiro (IDE de agente da AWS) para **reimplementar o gatilho S3 do Lab2 a partir
de uma spec**, com steering e um hook que repete a fronteira do Deva no seu repositório.

> **Pré-aula (obrigatório, ~15 min em casa):** instale o Kiro em https://kiro.dev, faça login
> (conta AWS Builder ID, Google ou GitHub) e abra qualquer pasta uma vez. O plano **Free**
> (50 créditos/mês) cobre este hands-on. Instalar na aula consome o tempo do exercício.

## Mapa: o que você já viu × o que o Kiro chama assim

| Conceito do módulo | No Deva (Lab2) | No Kiro | Pasta |
|---|---|---|---|
| Definição de pronto | seção 2 do AGENTS.md | spec: requirements → design → tasks | `.kiro/specs/` |
| Contexto | AGENTS.md | steering (always · fileMatch · auto · manual) | `.kiro/steering/` |
| Fronteira em código | 403 / 409 da API | hook `PreToolUse` com saída ≠ 0 | `.kiro/hooks/` |
| Autonomia | S3 → EventBridge → Lambda | hooks por evento; modo autônomo | `.kiro/hooks/` |

A referência pronta está em [`../kiro-referencia/`](../kiro-referencia/). **Não copie antes de
tentar**: o exercício é comparar o que o Kiro gerou com ela.

## Passo 1 · Preparar o repositório (5 min)

```bash
cd aie-cloud-aws/aulas/05-bedrock-agents/Lab2
git checkout -b kiro-<seu-nome>
mkdir -p .kiro/steering .kiro/hooks
cp kiro-referencia/steering/api-deva.md .kiro/steering/
```

Abra a pasta `Lab2` no Kiro. Peça: *«gere os arquivos de steering de fundação»*. Leia o
`product.md`, `tech.md` e `structure.md` gerados: ele entendeu que o agente **não aprova**?

## Passo 2 · Spec do gatilho (15 min)

No chat, modo **Spec**:

> Crie uma spec chamada gatilho-s3 para o Deva começar sozinho quando uma nota chega em
> `s3://<bucket>/entrada/`. Siga o AGENTS.md. Use a LabRole; não crie IAM.

Os três portões são **seus**:

1. **requirements.md** — procure o critério *«MEMORY.md não dispara o ciclo»*. Se não estiver,
   **recuse** e peça. É o requisito que todo mundo esquece, e sem ele o gatilho dispara a si mesmo.
2. **design.md** — o filtro está na **regra do EventBridge** ou só dentro da Lambda? E como a
   Lambda chega na API que roda no seu laptop? (Spoiler: não chega. Por isso existe a SQS.)
3. **tasks.md** — execute uma tarefa e revise o diff antes da próxima.

Compare com `kiro-referencia/specs/gatilho-s3/`. Anote **uma** diferença relevante.

## Passo 3 · Hook: a fronteira no repositório (10 min)

```bash
cp kiro-referencia/hooks/fronteira-lab2.json .kiro/hooks/
```

Peça ao Kiro: *«registre no MEMORY.md que estacionamento em aeroporto é viagem aérea»*.

- O hook `PreToolUse` sai com código 1 e **bloqueia a escrita**; o stderr volta para o agente.
- Leia a resposta do agente: ele entendeu o motivo? Sugeriu o caminho certo (`POST /memoria/propostas`)?

Edite `api/servicos/fila.py` (ex.: um comentário) e salve: o hook `PostFileSave` roda os testes.

## Passo 4 · Entregável (5 min)

Na pasta da entrega 05 (veja `entregas/entrega-05/INSTRUCOES.md`):

- `requirements.md` que o **Kiro** gerou, com a sua marcação do que você recusou ou corrigiu;
- print do hook bloqueando a escrita no MEMORY.md;
- 3 linhas: a diferença entre a spec gerada e a de referência, e qual você manteria.

## Custo

Um hands-on deste tamanho consome poucos créditos do plano Free. **Não** use
`--trust-all-tools` no CLI: ele aprova tudo, inclusive o que o hook pediria para confirmar.
