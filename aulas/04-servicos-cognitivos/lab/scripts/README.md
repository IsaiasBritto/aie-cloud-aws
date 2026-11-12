# Scripts auxiliares — Aula 4

| Script | Quando usar |
|--------|-------------|
| [semear_reviews.py](semear_reviews.py) | **Lab 1**: grava 10 reviews na tabela DynamoDB, sem credencial nenhuma (LabRole). Atalho: `qc semeia` |

```bash
source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/qc.sh   # exporta REVIEWS_TABLE e cria o qc
qc semeia
```

> O script não usa chave, senha ou host: o boto3 pega a credencial da sessão do CloudShell (LabRole). Rodar de novo regrava os itens e zera a análise de sentimento e de foto.
