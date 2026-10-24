# Exercícios — Aula 5 (Agentes com Amazon Bedrock)

Base de tudo: o [Lab2](Lab2/) (Deva contínuo). Rode `make testar` antes de começar: 25 casos verdes.

> **Perfil:** N1 é conceitual e não exige código. N2 exige Python básico e segue o padrão de código
> que já existe no Lab2. N3 é para quem quer ir além (bônus).

---

## 🟢 N1 — Conceitos (obrigatório)

### 1.1 Instrução × permissão
Liste **8 ações** que o Deva poderia tentar (ex.: aprovar reembolso, ler a memória, mudar a alçada,
propor regra, liberar exceção, apagar nota, comunicar o colaborador, registrar duplicado). Para cada
uma, diga **onde** o limite mora: só no `AGENTS.md` (instrução), na API (permissão) ou nos dois.
Justifique as que ficam **só** em instrução: o que acontece se o prompt falhar?

### 1.2 Os três freios, em reais
O `ciclo_do_agente.py` para em **8 voltas, 20 mil tokens ou 60 s**. A QC recebe 3.000 notas/mês.
Usando a página de preços do Bedrock (Claude Haiku 5.5, perfil `global.`), calcule:
(a) o custo **no pior caso** (toda execução bate os 20 mil tokens); (b) o custo com a média que
você mediu ou estimou; (c) qual freio você mudaria primeiro se a conta dobrasse, e por quê.

### 1.3 Memória: MEMORY.md assinado × AgentCore Memory
Compare as duas abordagens em quatro critérios: auditoria (quem escreveu?), revogação, custo e
esforço de operação. Em que cenário da QC você usaria cada uma? (Dica: o slide 43 tem a resposta
curta — "a resposta madura usa os dois". Explique o *como*.)

### 1.4 Excessive Agency (OWASP LLM06)
O OWASP lista três causas: funcionalidade, permissão e autonomia excessivas. Para cada uma, aponte
**a camada do Lab2** que a mitiga (veja a tabela do `Lab2/README.md`) e **uma** lacuna que ainda existe.

---

## 🟡 N2 — Mão no código (obrigatório)

### 2.1 Esquecimento — `POST /memoria/{id}/arquivar`
Hoje, ninguém apaga uma memória errada. De propósito. Implemente o arquivamento:
- só com `X-Auditor` (sem ele, ou com `deva` → 403);
- a linha **não some** do MEMORY.md: ela vai para uma seção `## Arquivadas`, com quem arquivou e o motivo;
- o agente **não** recebe essa operação (`openapi-agente.json` continua com 5).

Entregue: o código, **2 testes novos** e a resposta: *uma regra de 12 meses sem uso continua valendo?
Quem decide?*

### 2.2 Rastreabilidade
Cada decisão `extraido` já guarda `regra_aplicada`. Crie `GET /memoria/regras/{texto}/dependentes`
que lista os itens decididos com aquela regra. Ao arquivar (2.1), a resposta deve dizer quantos
itens dependiam dela. Entregue o código, 1 teste e um exemplo de saída.

### 2.3 Kiro — o agente que constrói o agente
Siga o [`Lab2/docs/kiro.md`](Lab2/docs/kiro.md) (instalação na pré-aula). Entregue:
- o `requirements.md` gerado pelo Kiro, marcando o que você **recusou ou corrigiu**;
- print do hook bloqueando a escrita no MEMORY.md;
- 3 linhas sobre a principal diferença entre a spec gerada e a de referência.

---

## 🔴 N3 — Bônus

### 3.1 Gatilho de ponta a ponta na AWS
Faça o Caminho B do `guia-lab.md` no Learner Lab: `make provisionar`, `make enviar`,
`make drenar`, 4 voltas. **Prove** com o log da Lambda que `entrada/MEMORY.md` foi ignorado.
Depois rode `make limpar` e mostre que não sobrou recurso `deva-lab2-*`.

### 3.2 Taxa de devolução: prove que o problema é a regra
Crie 10 notas novas em `gatilho/amostras/` que levem a taxa de devolução acima de 30%. Depois,
**sem mexer no código do agente**, só aprovando propostas, traga a taxa para baixo de 30%. Mostre o
painel antes e depois.

### 3.3 Segunda opinião
Um segundo agente critica cada proposta antes de ela chegar ao auditor (pode ser regra em Python
ou LLM). Ajuda, ou vira teatro? Meça: quantas propostas ruins ele barrou, e quantas boas ele atrasou.

### 3.4 Troque o modelo, não a fronteira (conta própria, não Learner Lab)
Rode `ciclo_do_agente.py --uma-volta --bedrock` com dois modelos (`BEDROCK_MODEL_ID`). Compare
tokens, voltas e decisões. Rode `make demos` com cada um: o resultado da fronteira muda? Por quê não?
