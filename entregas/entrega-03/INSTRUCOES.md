# Entrega 03 — Aula 3 (Serverless & Containers)

**Vale:** 10% da nota final
**Prazo:** até 1 dia antes da Aula 4
**Onde:** upload de UM ZIP no Portal FIAP (combine no grupo quem faz)

---

## O que entregar

| Item | Obrigatório? | Pontos máximos |
|------|--------------|----------------|
| Cabeçalho do grupo + distribuição do trabalho | ✅ Sim | 1 pt (Critério 4) |
| 🟢 N1 — Exercícios 1.1 (quando usar serverless), 1.2 (IAM Role vs alternativas e a policy mínima da ferramenta), 1.3 (cold start), 1.4 (Dockerfile review) | ✅ Sim | 3 pts (Critério 1) |
| 🟡 N2 — Exercício 2.1 no [canvas de compute](canvas-compute.md) (5 cargas, com custo), 2.2 (segunda tool: cálculo de frete), 2.3 (CloudWatch) | ✅ Sim | 3 pts (Critério 2) + 2 pts qualidade técnica (Critério 3) |
| 🔴 N3 — 3.1 (spec de tool de agente), 3.2 (benchmark), 3.3 (CI/CD GitHub Actions + OIDC), 3.4 (Fargate em produção) | 🎁 Bônus | até +2 pts extras |
| Reflexão coletiva ao final, com a linha do canvas de cada membro (uma carga real do trabalho, anonimizada) | ✅ Sim | 1 pt (Critério 5) |
| **Total** | | **10 pts** |

Conteúdo dos exercícios: [aulas/03-serverless-containers/exercicios.md](../../aulas/03-serverless-containers/exercicios.md).

---

## Estrutura do ZIP

Nome: `entrega-grupo-NN-aula03.zip`.

```
qc-grupo-NN-aula03/
├── entrega-grupo-aula03.md       # ⭐ documento principal (template em ../template-entrega-grupo.md)
├── canvas-compute.md             # N2: o canvas preenchido (template em canvas-compute.md)
├── README.md                     # Como rodar o que foi entregue
├── terraform/                    # main.tf evoluído (Lambda + Function URL + ECR + ECS Fargate + alarme do N2.3)
├── function/                     # Código Python da Lambda (incluindo a tool de frete do N2.2)
├── docker/                       # Dockerfile + app.py FastAPI (se entregue)
├── .github/workflows/            # Workflow CI/CD (se N3.3)
└── diagramas/
    └── arquitetura-qc-aula03.png # Diagrama da QC com a camada de API/compute
```

**NÃO incluir:** `terraform.tfstate*`, `.env`, `*.pem`, `__pycache__/`, `.venv/`, imagens Docker locais.

---

## Como gerar e enviar

```bash
cd ~/qc-grupo-NN
git pull origin main
git archive --format=zip --prefix=qc-grupo-NN-aula03/ -o ~/entrega-grupo-NN-aula03.zip HEAD:aula03
unzip -l ~/entrega-grupo-NN-aula03.zip
```

Upload no Portal FIAP, tarefa "Entrega Aula 3".

---

## Critérios de avaliação

[Rubrica única](../rubrica.md). **Foco específico desta entrega:**

- **N1:** dominar a decisão **Lambda / ECS Fargate / ECS Express Mode / EKS** por caso de uso e o conceito de **IAM Role** (execution role, task role) como substituto a credenciais, com a **policy mínima** da ferramenta (só o `catalogo/`).
- **N2:** o **[canvas de compute](canvas-compute.md)** da QC (5 cargas), começado em sala no Bloco 4: para cada carga, como é chamada, quanto roda, tráfego, tolerância a cold start, identidade, custo estimado na calculadora AWS e onde roda (serviço + justificativa). É a peça central desta entrega. A tool de **cálculo de frete** entra como segunda tool consumida pelos agentes, e o **CloudWatch** (logs, métricas, alarme) mostra domínio operacional.
- **N3 (bônus):** o exercício **3.1 (spec de tool)** é o mais valorizado — é o contrato entre o agente e a API que vocês construíram. Bem feito, é peça do projeto integrado final.
- **Reflexão:** discutir como a escolha "Lambda vs Container" muda a forma como o agente consome a tool (cold start, latência, falhas) e o que isso implica para a UX da QC. Inclua a linha do canvas de cada membro, com uma carga real do trabalho, anonimizada.

---

## Rotação esperada

Quem fez N1 nas Aulas 1-2 deve preferencialmente assumir **N2** ou **N3** aqui (Critério 4 — Distribuição). O cabeçalho `Distribuição do trabalho` é a evidência.
