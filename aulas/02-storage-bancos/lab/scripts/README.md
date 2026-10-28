# Scripts Python — Aula 2

Os scripts que o comando `qc` chama. Todos usam o **boto3**, que no CloudShell autentica sozinho com a credencial da sessão do Learner Lab: nenhuma chave no código.

```bash
source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh   # uma vez por sessão
qc                                                    # lista os comandos
```

| Comando | Script | Lab | O que faz |
|---------|--------|-----|-----------|
| `qc lake gera` | [gerar_pedidos.py](gerar_pedidos.py) | 1B | Gera ~200 mil pedidos sintéticos (semente fixa, só biblioteca padrão) para a camada `raw/` do lake; o `qc lake cura` e o `qc lake compara` rodam SQL no Athena |
| `qc carga produtos` | [popular_produtos.py](popular_produtos.py) | 2 | Lê a connection string do Secrets Manager e o CSV do S3; cria e popula `t_produtos` no RDS |
| `qc sql "SELECT ..."` | [consultar.py](consultar.py) | 2 | Roda uma consulta no RDS e mostra o resultado em colunas |
| `qc carga reviews` | [popular_reviews.py](popular_reviews.py) | 3A | Grava 30 reviews fictícias no DynamoDB e consulta a partição `produto_id = 5` |
| `qc indexa` | [indexar_produtos.py](indexar_produtos.py) | 3B | Gera embeddings (MiniLM, 384 dimensões) e cria `produtos_vetor` com índice HNSW no pgvector |
| `qc busca "texto"` | [buscar_produtos.py](buscar_produtos.py) | 3B | A mesma pergunta por palavra e pelo sentido, lado a lado |
| `qc sentimento` | [analisar_sentimento.py](analisar_sentimento.py) | Aula 4 | Sentimento das reviews com o Comprehend (conta do professor) ou por regras, sem IA (Learner Lab); o tema saiu desta aula |

## Dependências

O `qc` instala no venv `/tmp/venv-qc`, na primeira vez, só o que cada comando precisa. Para instalar tudo de uma vez:

```bash
source /tmp/venv-qc/bin/activate   # o source do qc.sh já faz isso
pip install --no-cache-dir -r requirements.txt
```

> O venv fica em `/tmp` porque o `$HOME` do CloudShell tem só 1 GB. O `/tmp` é limpo quando a sessão reinicia: o `qc` reinstala sozinho quando precisar.

> **Lição de segurança:** a credencial nunca aparece no código. No CloudShell ela vem da sessão; numa Lambda ou tarefa ECS, da execution/task role; no seu notebook, do `aws configure` ou de SSO. O código é o mesmo nos três lugares.
