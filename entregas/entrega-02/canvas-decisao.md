# Canvas de decisão de dados — Quantum Commerce

**Grupo:** NN · **Entrega 02 · N2**

Uma linha por dado. As colunas são as perguntas que decidem onde ele mora; a última é a decisão.

| Coluna | A pergunta por trás |
|--------|---------------------|
| Que pergunta responde | O que o agente, o cliente ou o time pergunta a esse dado? |
| Volume e crescimento | Quanto é hoje, e quanto cresce por mês? |
| Pode errar? | Pode ficar desatualizado por um minuto, ou envolve dinheiro? |
| Quem lê / credencial | Quem acessa, e onde fica a senha ou a role? |
| Custo/mês | Estimativa na [calculadora AWS](https://calculator.aws), região `us-east-1` |
| Onde mora e por quê | Serviço AWS + uma frase de justificativa (e o que vocês **não** usariam) |

## Os 9 domínios da QC

Volumes do [Exercício 2.1](../../aulas/02-storage-bancos/exercicios.md). A primeira linha é o exemplo feito em sala.

| Dado | Que pergunta responde | Volume e crescimento | Pode errar? | Quem lê / credencial | Custo/mês | Onde mora e por quê |
|------|-----------------------|----------------------|-------------|----------------------|-----------|---------------------|
| Reviews | O que os clientes acham deste produto? | ~30M textos | Sim (minutos) | Agente de atendimento, pela role | | DynamoDB: sempre lido por produto (partition key) |
| Produtos (5M SKUs) | | | | | | |
| Clientes (~50M) | | | | | | |
| Pedidos (~10M/mês) | | | | | | |
| Carrinhos ativos (~500k) | | | | | | |
| Busca de produtos | | | | | | |
| Sessões (~1M) | | | | | | |
| Histórico de navegação | | | | | | |
| Modelos de ML | | | | | | |

## Uma linha do trabalho de vocês

Cada membro do grupo, uma linha com um dado real do próprio trabalho. Anonimizem nomes, números e clientes.

| Membro | Dado | Que pergunta responde | Volume e crescimento | Pode errar? | Quem lê / credencial | Custo/mês | Onde mora hoje — e onde deveria morar |
|--------|------|-----------------------|----------------------|-------------|----------------------|-----------|---------------------------------------|
| | | | | | | | |
