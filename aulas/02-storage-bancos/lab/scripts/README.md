# Scripts Python — Aula 2

Scripts que populam e exploram as bases provisionadas pelo Terraform da Aula 2. Todos usam o **boto3**, que no CloudShell autentica sozinho com a credencial da sessão do Learner Lab (LabRole) — nenhuma chave no código.

| Script | Atividade | O que faz |
|--------|-----------|-----------|
| [popular_produtos.py](popular_produtos.py) | L₂ | Lê a connection string do Secrets Manager e o CSV do S3; cria e popula `t_produtos` no RDS PostgreSQL |
| [popular_reviews.py](popular_reviews.py) | L₃-A | Insere 30 reviews fictícias no DynamoDB e faz Query na partição `produto_id = 5` |
| [indexar_produtos.py](indexar_produtos.py) | L₃-B | Gera embeddings (MiniLM, 384 dims) e cria a busca vetorial com pgvector no RDS |

## Dependências

```bash
# Fora do $HOME do CloudShell, que tem só 1 GB (o fastembed e o onnxruntime somam centenas de MB)
python3 -m venv /tmp/venv-qc && source /tmp/venv-qc/bin/activate
pip install --no-cache-dir -r requirements.txt
# ou só o que cada atividade pede (ver guia)
```

> `/tmp` é limpo quando a sessão reinicia. Se aparecer `ModuleNotFoundError`, recrie e ative o venv (`python3 -m venv /tmp/venv-qc && source /tmp/venv-qc/bin/activate`) e rode o `pip install` de novo.

## Variáveis de ambiente

| Script | Variáveis |
|--------|-----------|
| `popular_produtos.py` | `SECRET_ID`, `BUCKET_NAME` |
| `popular_reviews.py` | `DYNAMO_TABLE` |
| `indexar_produtos.py` | `SECRET_ID` (ou `DB_HOST` + `DB_PASSWORD`), `BUCKET_NAME` |

Todas de uma vez, a partir dos outputs do Terraform (também ativa o venv de `/tmp/venv-qc` e recupera a `DB_PASSWORD`):

```bash
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
```

## Como executar

```bash
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 popular_produtos.py
python3 popular_reviews.py
python3 indexar_produtos.py
```

> **Lição de segurança:** a credencial nunca aparece no código. No CloudShell ela vem da sessão; numa Lambda ou tarefa ECS, da execution/task role; no seu notebook, do `aws configure` ou de SSO. O código é o mesmo nos três lugares.
