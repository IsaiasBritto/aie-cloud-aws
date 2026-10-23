# Scripts Python — Aula 2

Scripts que populam e exploram as bases provisionadas pelo Terraform da Aula 2. Todos usam o **boto3**, que no CloudShell autentica sozinho com a credencial da sessão do Learner Lab (LabRole) — nenhuma chave no código.

| Script | Atividade | O que faz |
|--------|-----------|-----------|
| [popular_produtos.py](popular_produtos.py) | L₂ | Lê a connection string do Secrets Manager e o CSV do S3; cria e popula `t_produtos` no RDS PostgreSQL |
| [popular_reviews.py](popular_reviews.py) | L₃-A | Insere 30 reviews fictícias no DynamoDB e faz Query na partição `produto_id = 5` |
| [indexar_produtos.py](indexar_produtos.py) | L₃-B | Gera embeddings (MiniLM, 384 dims) e cria a busca vetorial com pgvector no RDS |
| [popular_reviews_mongo.py](popular_reviews_mongo.py) | L₃-C (demo) | Mesmas 30 reviews no MongoDB da EC2, com a senha lida do Secrets Manager. Só com `TF_VAR_criar_mongo=true` no apply |

## Dependências

```bash
# Fora do $HOME do CloudShell, que tem só 1 GB (o fastembed e o onnxruntime somam centenas de MB)
export PYTHONUSERBASE=/tmp/pyuser
pip install --user --no-cache-dir -r requirements.txt
# ou só o que cada atividade pede (ver guia)
```

> `/tmp` é limpo quando a sessão reinicia. Se aparecer `ModuleNotFoundError`, exporte o `PYTHONUSERBASE` e rode o `pip install` de novo.

## Variáveis de ambiente

| Script | Variáveis |
|--------|-----------|
| `popular_produtos.py` | `SECRET_ID`, `BUCKET_NAME` |
| `popular_reviews.py` | `DYNAMO_TABLE` |
| `indexar_produtos.py` | `SECRET_ID` (ou `DB_HOST` + `DB_PASSWORD`), `BUCKET_NAME` |
| `popular_reviews_mongo.py` | `MONGO_IP`, `MONGO_SECRET_ID` (ou `SECRET_ID`) |

Todas de uma vez, a partir dos outputs do Terraform (inclui `PYTHONUSERBASE` e a `DB_PASSWORD`):

```bash
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
```

## Como executar

```bash
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 popular_produtos.py
python3 popular_reviews.py
python3 indexar_produtos.py
python3 popular_reviews_mongo.py
```

> **Lição de segurança:** a credencial nunca aparece no código. No CloudShell ela vem da sessão; numa Lambda ou tarefa ECS, da execution/task role; no seu notebook, do `aws configure` ou de SSO. O código é o mesmo nos três lugares.
