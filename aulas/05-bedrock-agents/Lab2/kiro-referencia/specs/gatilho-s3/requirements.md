# Requisitos — gatilho S3 do Lab2

## Introdução
O Deva hoje só trabalha quando alguém roda `disparador.py --semear`. Este gatilho faz o agente
começar sozinho quando uma nota de despesa chega no bucket — sem nunca disparar a si mesmo.

## Requisito 1 — o agente começa sozinho
**História:** como auditor, quero que uma nota enviada ao bucket entre na fila sem ninguém
rodar comando, para que o agente trabalhe de forma contínua.

### Critérios de aceite
1. WHEN um objeto é criado no prefixo `entrada/` do bucket
   THE SYSTEM SHALL criar um item na fila da API em até 60 s
2. WHEN o objeto gravado for `MEMORY.md` ou `memoria-pendente.md`, em qualquer prefixo
   THE SYSTEM SHALL NOT disparar o ciclo do agente
3. WHEN o mesmo conteúdo chegar duas vezes
   THE SYSTEM SHALL marcar o segundo item como `duplicado`
4. WHEN a API estiver fora do ar
   THE SYSTEM SHALL manter o aviso na fila SQS por até 24 h, sem perder a nota

## Requisito 2 — o gatilho não ganha poder
1. THE SYSTEM SHALL NOT criar nenhuma IAM role (a Lambda usa a LabRole do Learner Lab)
2. THE SYSTEM SHALL NOT dar ao gatilho acesso a operações de aprovação da API
