# Entrega 05 — Aula 5 (Agentes com Amazon Bedrock)

**Vale:** 10% da nota final
**Prazo:** até 1 dia antes da Aula 6
**Onde:** upload de UM ZIP no Portal FIAP (combine no grupo quem faz)

> **Última entrega intermediária!** A Aula 6 é dedicada ao **trabalho assistido em grupo no projeto integrado final** (50% da nota, **entrega ZIP 1 semana após a aula, sem apresentação oral**) — ver [projeto-final/](../projeto-final/).

> **MLOps virou material complementar.** O conteúdo de SageMaker AI continua em
> [aulas/05-mlops/](../../aulas/05-mlops/) para estudo, mas **não é cobrado nesta entrega**.

---

## ⚠️ Atenção custo

Se você fez o **N3.1 (gatilho na AWS)**, rode `make limpar` na pasta `Lab2` **antes de entregar**.
Bucket, SQS e Lambda custam centavos, mas o orçamento do Learner Lab é da turma inteira.
Se usou **Bedrock numa conta própria (N3.4)**, confira o Cost Explorer: o freio de 20 mil tokens
vale por execução, não por mês.

---

## O que entregar

| Item | Obrigatório? | Pontos máximos |
|------|--------------|----------------|
| Cabeçalho do grupo + distribuição do trabalho | ✅ Sim | 1 pt (Critério 4) |
| 🟢 N1 — 1.1 (instrução × permissão), 1.2 (os três freios em reais), 1.3 (MEMORY.md × AgentCore Memory), 1.4 (Excessive Agency) | ✅ Sim | 3 pts (Critério 1) |
| 🟡 N2 — 2.1 (arquivar memória + testes), 2.2 (rastreabilidade), 2.3 (Kiro: spec + hook) | ✅ Sim | 3 pts (Critério 2) + 2 pts qualidade técnica (Critério 3) |
| 🔴 N3 — 3.1 (gatilho na AWS), 3.2 (taxa de devolução), 3.3 (segunda opinião), 3.4 (troque o modelo) | 🎁 Bônus | até +2 pts extras |
| Reflexão coletiva ao final | ✅ Sim | 1 pt (Critério 5) |
| **Total** | | **10 pts** |

Conteúdo dos exercícios: [aulas/05-bedrock-agents/exercicios.md](../../aulas/05-bedrock-agents/exercicios.md).

> **Perfil dos alunos:** N1 é conceitual. N2 exige Python básico e segue o padrão do Lab2 (os testes existentes são o modelo). N3 é para quem quer ir além.

---

## Estrutura do ZIP

Nome: `entrega-grupo-NN-aula05.zip`.

```
qc-grupo-NN-aula05/
├── entrega-grupo-aula05.md       # ⭐ documento principal (template em ../template-entrega-grupo.md)
├── lab2/                         # SÓ o que vocês mudaram ou criaram no Lab2
│   ├── api/                      # arquivar (2.1) e dependentes (2.2)
│   ├── api/testes/               # os testes novos
│   └── agente/openapi-agente.json  # tem que continuar com 5 operações
├── kiro/
│   ├── requirements.md           # gerado pelo Kiro, com a marcação de vocês (2.3)
│   └── hook-bloqueando.png       # print do hook barrando o MEMORY.md
└── evidencias/                   # prints e logs do N3 (se entregue)
```

Anexar também no `entrega-grupo-aula05.md`:

- **Saída do `make testar`** com os testes novos passando (o número tem que ser maior que 25)
- **Tabela** do N1.1 (8 ações × onde mora o limite)
- **Conta** do N1.2, com o link da página de preços e a data da consulta
- **Exemplo de saída** do `GET /memoria/regras/.../dependentes` (N2.2)

**NÃO incluir:** `dados/`, `.venv/`, `terraform.tfstate*`, `.terraform/`, `*.zip`, `__pycache__/`, `.env`. Credenciais do Learner Lab — **nunca commitar**.

---

## Como gerar e enviar

```bash
cd ~/qc-grupo-NN
git pull origin main
git archive --format=zip --prefix=qc-grupo-NN-aula05/ -o ~/entrega-grupo-NN-aula05.zip HEAD:aula05
unzip -l ~/entrega-grupo-NN-aula05.zip
```

Upload no Portal FIAP, tarefa "Entrega Aula 5".

---

## Critérios de avaliação

[Rubrica única](../rubrica.md). **Foco específico desta entrega:**

- **N1:** separar **instrução** (o que o agente deveria fazer) de **permissão** (o que ele consegue fazer). Resposta que coloca tudo no prompt perde ponto no 1.1.
- **N2:** o arquivamento (2.1) **não pode** virar uma operação do agente. O corretor confere três coisas: 403 sem `X-Auditor`, a linha arquivada continua visível no MEMORY.md, e `openapi-agente.json` com 5 operações.
- **N2.3:** vale mais **o que vocês recusaram** na spec do Kiro do que a spec em si. O requisito do MEMORY.md não disparar o gatilho é o que se espera ver.
- **Reflexão:** que decisão da QC vocês **nunca** deixariam um agente tomar sozinho, mesmo com a melhor avaliação do mundo? Onde essa fronteira mora no código de vocês?

---

## Rotação esperada

Esta é a **última oportunidade de rodízio** antes da entrega final. Quem fez N1 nas Aulas 1-4 deve, idealmente, assumir N2 ou N3 nesta entrega (Critério 4 — Distribuição do trabalho).

---

## Já comece a consolidar para a Aula 6

A Aula 6 é dedicada ao **projeto integrado final** (50% da nota, ZIP no Portal FIAP **1 semana após a aula**, sem apresentação oral). O que adiantar agora:

1. **Diagrama final** da arquitetura QC com **todas as camadas** (Aulas 1-5), incluindo o agente e a fronteira
2. **Terraform consolidado** que provisiona TODA a arquitetura da QC
3. **5 tools** documentadas: `/produtos`, `/transcrever`, `/analisar-reviews`, `/analisar-imagem`, `/recomendar` — e **quais delas o agente recebe**
4. **Esboço da análise FinOps** — AWS Pricing Calculator com todos os componentes

Detalhes da entrega final em [../projeto-final/INSTRUCOES.md](../projeto-final/INSTRUCOES.md).
