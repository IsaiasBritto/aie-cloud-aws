# Canvas de compute — Quantum Commerce

**Grupo:** NN · **Entrega 03 · N2**

Uma linha por carga de trabalho. As colunas são as perguntas que decidem onde ela roda; a última é a decisão.

| Coluna | A pergunta por trás |
|--------|---------------------|
| Como é chamada | Por HTTP (o agente, o site), por evento (fila, arquivo novo) ou por agenda? |
| Quanto tempo roda | Milissegundos, minutos ou horas? (a Lambda para em 15 minutos) |
| Tráfego | Em picos, constante ou parado boa parte do dia? |
| Espera 1 s? | O usuário aguenta esperar a primeira chamada (cold start)? |
| Identidade | Com que role ela roda, e o que essa role pode ler? Só o necessário? |
| Custo/mês | Estimativa na [calculadora AWS](https://calculator.aws), região `us-east-1`, na casa escolhida e na outra |
| Onde roda e por quê | Lambda, Fargate ou outro + uma frase de justificativa (e o que vocês **não** usariam) |

## As 5 cargas da QC

A primeira linha é o exemplo feito em sala.

| Carga | Como é chamada | Quanto tempo roda | Tráfego | Espera 1 s? | Identidade | Custo/mês | Onde roda e por quê |
|-------|----------------|-------------------|---------|-------------|------------|-----------|---------------------|
| Busca no catálogo (`buscar_produtos`) | O agente, por HTTP | < 1 s | Picos; parada de madrugada | Sim | Só `s3:GetObject` no `catalogo/` | | Lambda: paga por chamada e parada custa zero |
| Cálculo de frete | | | | | | | |
| Notas fiscais (geração noturna) | | | | | | | |
| Recomendação de produtos | | | | | | | |
| Checkout | | | | | | | |

## Uma linha do trabalho de vocês

Cada membro do grupo, uma linha com uma carga real do próprio trabalho. Anonimizem nomes, sistemas, números e clientes.

| Membro | Carga | Como é chamada | Quanto tempo roda | Tráfego | Espera 1 s? | Identidade | Custo/mês | Onde roda hoje — e onde deveria rodar |
|--------|-------|----------------|-------------------|---------|-------------|------------|-----------|---------------------------------------|
| | | | | | | | | |
