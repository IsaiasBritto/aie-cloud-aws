# Aula 5 — Criando Agentes com Amazon Bedrock

Do laço de um agente ao que a empresa precisa para aceitá-lo: identidade, custo, autonomia
controlada e uma fronteira escrita em código. O lab da turma é o Deva contínuo (Lab2), com o
Kiro aplicado sobre ele.

> ⚠️ **O AWS Academy Learner Lab não libera o Bedrock.** Por isso a parte com Bedrock é
> **demonstração do professor**, numa conta comum. O lab da turma (Lab2) roda sem LLM, com o
> mesmo contrato de ferramentas que o modelo usaria.

| Pasta | O que é | Onde roda | Em sala |
|---|---|---|---|
| [Lab2/](Lab2/) | **Deva contínuo**: gatilho S3 → EventBridge → Lambda → SQS, fila com máquina de estados e **memória revisável** (o agente propõe, o auditor assina). Inclui o hands-on do **Kiro** | sua máquina · CloudShell | **lab da turma** (45 min) + Kiro (40 min) |
| [01-agente-Eva-local/](01-agente-Eva-local/) | A Eva: laço, ferramentas, `agent.md` e `memory.md` | máquina do professor (OpenAI) | demo curta no Bloco 1 |
| [02-agente-Eva-local-to-bedrock/](02-agente-Eva-local-to-bedrock/) | A mesma Eva falando com a API **Converse** | conta do professor | demo no Bloco 3 |
| [agentebase/](agentebase/) | O esqueleto mínimo de um agente (~200 linhas) | sua máquina (OpenAI) | complementar |
| [Lab/](Lab/) | **Deva3**: validação biométrica com **Rekognition**, S3 e ECS | Learner Lab | complementar |
| [03-agente-Eva-aws/](03-agente-Eva-aws/) | A Eva no **ECS Fargate**, com telemetria e FinOps no CloudWatch | Learner Lab (`provedor = openai`) | complementar, ponte para a Aula 6 |

## Ordem em sala

1. Blocos 1 a 5 do deck (conceitos, plataforma, modelo, custo, estratégia). No Bloco 1 o professor
   mostra a Eva local rodando com uma chave de projeto da OpenAI; no Bloco 3, a mesma Eva no
   Bedrock. A chave é do professor, tem limite de gasto e é revogada depois da aula.
2. `Lab2/` (turma, 45 min): o agente trabalha sozinho e a **fronteira em código** segura o que o
   prompt não segura, com 403, 409 e 422 ao vivo. Guia: [Lab2/guia-lab.md](Lab2/guia-lab.md).
3. Kiro (turma, 40 min, **instalação na pré-aula**): spec, steering e hook sobre o próprio Lab2.
   Guia: [Lab2/docs/kiro.md](Lab2/docs/kiro.md).

A Entrega 05 cobra só o Lab2 e o Kiro. Deva3, Eva no ECS e `agentebase` ficam como material
complementar: rodam no Learner Lab (validados em 16/11/2026, cada deploy leva de 3 a 5 minutos),
e quem fizer a Eva no ECS chega na Aula 6 com telemetria de custo para analisar. Para a Eva fora
da aula, cada aluno usa a própria chave da OpenAI.

Exercícios: [exercicios.md](exercicios.md) · Entrega: [entrega-05](../../entregas/entrega-05/INSTRUCOES.md).
O conteúdo de MLOps com SageMaker AI virou [material complementar](../05-mlops/).

## Custos e limpeza

Tudo que roda no ECS cobra **enquanto está ligado**. Ao fim da aula:

```bash
bash Lab/infra/99-remover-tudo.sh
bash Lab2/infra/99-remover-tudo.sh
terraform -chdir=03-agente-Eva-aws/infra/terraform destroy -auto-approve
```
