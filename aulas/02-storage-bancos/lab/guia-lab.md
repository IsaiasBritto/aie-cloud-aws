# Guia de Laboratório — Aula 2

**Tema:** Storage & Bancos de Dados na Nuvem — onde os dados dos agentes vivem
**Plataforma:** AWS Academy Learner Lab · **Ambiente:** AWS CloudShell · **Região:** `us-east-1`

Cada lab tem o mesmo ritmo: **um comando no terminal, a verificação no console, uma pergunta para o grupo responder**. O que é encanamento (venv, pip, variáveis, senha) fica no atalho `qc`. Os passos técnicos detalhados de cada banco estão no [guia de aprofundamento](guia-aprofundamento.md).

---

## A aula em uma página

A aula responde a três perguntas que um cliente faz ao agente da Quantum Commerce (QC). Cada uma pede um dado guardado de um jeito diferente:

| Pergunta do cliente | Dado | Onde mora | Lab |
|---------------------|------|-----------|-----|
| "Tem cadeira boa pra coluna até R$ 1.500?" | Catálogo: preço exato + sentido | RDS PostgreSQL + pgvector | 2 e 3B |
| "O que os clientes acham dessa cadeira?" | Reviews: texto livre, lido por produto | DynamoDB | 3A |
| "Me mostra a nota fiscal da minha compra" | Arquivos: não mudam, guardados por anos | S3 + lifecycle | 1 |

E uma pergunta que não é do cliente, mas do negócio: **"quanto vendemos de cadeiras em setembro?"**. Ela não se responde no banco do dia a dia, e sim no data lake (Lab 1B).

```
00:00  Abertura — limpeza da Aula 1 + terraform apply                ~15 min
00:15  Bloco 1 — Arquivos: guardar e consultar     · Labs 1 e 1B    ~60 min
01:15  Bloco 2 — Dado que não pode errar            · Lab 2          ~50 min
02:05  Intervalo                                                      15 min
02:20  Bloco 3 — Forma e sentido                    · Labs 3A e 3B   ~55 min
03:15  Bloco 4 — A decisão: canvas em grupo + destroy                ~60 min
```

> **Regra de ouro:** a aula termina com `terraform destroy`.

---

## Abertura (~15 min)

### 1. Limpe a Aula 1 (~5 min)

1. Console **EC2** → **Instances** → filtre pela tag `aula = 1`
2. **Instance state → Terminate instance**
3. Apague o security group criado pelo console e o Resource Group `rg-lab-aula01`

> A Atividade 5 da Aula 1 (a mesma EC2 via Terraform) fica como tarefa: o roteiro está no [guia da Aula 1](../../01-fundamentos-iac/lab/guia-lab.md#atividade-5--terraform-recriar-a-mesma-ec2-via-iac).

### 2. Dispare a infraestrutura da aula

O RDS leva de 10 a 15 minutos para subir. Dispare agora; enquanto ele roda, a turma discute as três perguntas.

```bash
# Ainda não clonou? Clone:
cd ~ && git clone https://github.com/IsaiasBritto/aie-cloud-aws.git aie-cloud

# Já clonou na Aula 1? Atualize SEM apagar a pasta (ela guarda o terraform.tfstate da Aula 1):
git -C ~/aie-cloud stash && git -C ~/aie-cloud pull

cd ~/aie-cloud/aulas/02-storage-bancos/lab/terraform

# Terraform no $HOME (só se ainda não instalou na Aula 1)
bash ~/aie-cloud/aulas/01-fundamentos-iac/lab/install_terraform.sh
export PATH="$HOME/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Pré-voo: a sessão alcança S3, RDS, DynamoDB e Secrets Manager?
bash ../check_regions.sh

# Senha do RDS: gerada aqui, vai para o Secrets Manager e não fica em arquivo nenhum
export DB_PASSWORD=$(openssl rand -hex 16)

terraform init
terraform apply -auto-approve -var="db_password=$DB_PASSWORD"
```

O `apply` cria: bucket S3 (com 3 prefixos e uma regra de lifecycle), RDS PostgreSQL 16, o segredo com a connection string, a tabela DynamoDB de reviews e o workgroup do Athena.

### 3. Prepare a sessão (depois que o apply terminar)

```bash
source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh
qc            # mostra os comandos do lab
```

O [`qc.sh`](qc.sh) lê os outputs do Terraform, recupera a senha do Secrets Manager, ativa um venv Python em `/tmp` e cria o comando `qc`. Cada `qc` instala sozinho, na primeira vez, o que o script dele precisa.

> **A sessão do CloudShell caiu** (ele encerra depois de ~20 min sem uso)? Rode o mesmo `source`. O estado do Terraform fica no `$HOME`, então nada se perde. Se o IP do CloudShell mudou, o `source` avisa e mostra o comando que libera o IP novo no RDS.

---

## Lab 1 — O catálogo no S3 e a regra que o esfria (Bloco 1, ~20 min)

**Comando**

```bash
qc carga catalogo
```

**Console**

1. **S3 → Buckets → `qc-aula02-xxxxxx` → `catalogo/` → `produtos.csv`**. Na aba **Properties**, veja a classe (Standard), o tamanho e a criptografia (SSE-S3).
2. Volte ao bucket → aba **Management** → **Lifecycle rules**. Abra a regra `logs-lifecycle`, criada pelo Terraform: o que está em `logs/` vai para Standard-IA em 30 dias, para Glacier em 90 e é apagado em 1 ano.

   > Não crie regras pelo console: elas entram na mesma configuração que o Terraform gerencia, e o próximo `terraform apply` as apagaria. Mudança de regra se faz no [`storage.tf`](terraform/storage.tf).

3. **SQL direto no arquivo, com o Athena.** Entre pelo link do editor clássico: **https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/query-editor**

   > Não use a página inicial do Athena: ela leva ao SageMaker Unified Studio, bloqueado no Learner Lab (`datazone:ListDomains`).

   - Canto superior direito, **Workgroup**: `qc-aula02-xxxxxx`. À esquerda: **Data source** `AwsDataCatalog`, **Database** `qc`.
   - Troque o nome do bucket (`echo $BUCKET_NAME` no terminal) e rode:

```sql
CREATE EXTERNAL TABLE qc.produtos (
  id int, nome string, descricao string,
  categoria string, preco double, estoque int
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://qc-aula02-xxxxxx/catalogo/'
TBLPROPERTIES ('skip.header.line.count' = '1');

SELECT * FROM qc.produtos ORDER BY id LIMIT 5;

SELECT categoria, COUNT(*) AS qtd, ROUND(AVG(preco), 2) AS preco_medio
FROM qc.produtos GROUP BY categoria ORDER BY categoria;
```

Repare no **Data scanned**: o Athena cobra pelo volume lido (US$ 5 por TB). A "tabela" não copiou nada; é só uma definição aplicada a cada leitura (*schema-on-read*).

> Sem console? `qc athena "SELECT categoria, COUNT(*) FROM produtos GROUP BY categoria"` roda o mesmo SQL no terminal (depois do `CREATE`).

**Pergunta para o grupo:** que dados da QC esfriam rápido? Que regra de lifecycle vocês escreveriam para as notas fiscais, que precisam ficar 5 anos guardadas?

**✅ Checkpoint:** o `produtos.csv` está em `catalogo/` e o Athena devolveu as 6 categorias?

---

## Lab 1B — O lake da QC: o mesmo dado, dois formatos (Bloco 1, ~8 min)

O Lab 1 já é um data lake pequeno: o arquivo fica no S3 e o Athena consulta sem carregar nada em banco. Aqui o lake ganha as duas camadas e uma conta de custo.

**Comandos**

```bash
qc lake gera      # ~200 mil pedidos sintéticos → raw/pedidos/ + tabela qc.pedidos_raw (CSV)
qc lake cura      # CTAS no Athena: o mesmo dado em Parquet, particionado por mês → curated/pedidos/
qc lake compara   # a mesma pergunta nas duas tabelas: resultado, bytes lidos e o custo em 1 TB
```

- O `qc lake gera` cria cerca de 200 mil pedidos de 12 meses (semente fixa: todos os grupos geram o mesmo arquivo, ~13 MB), sobe em `raw/pedidos/` e cria a tabela `qc.pedidos_raw` sobre o CSV, como o `CREATE EXTERNAL TABLE` do Lab 1.
- O `qc lake cura` roda uma consulta **CTAS** (`CREATE TABLE ... AS SELECT`) no próprio Athena: ele lê o CSV e grava o mesmo dado em **Parquet** (colunar e comprimido), com uma pasta por mês (`mes=2026-09/`). Nenhum serviço novo.
- O `qc lake compara` faz a pergunta "faturamento por categoria em setembro" nas duas tabelas e mostra o resultado, os bytes lidos e a projeção para um CSV de 1 TB.

**Console**

1. **S3 → `qc-aula02-xxxxxx` → `raw/pedidos/`**: um CSV. Depois, **`curated/pedidos/`**: uma pasta por mês, com arquivos bem menores.
2. **Athena → Recent queries**: a coluna **Data scanned** das duas consultas do `qc lake compara`. O resultado é o mesmo; o volume lido, não.

> No lab a fatura é de centavos: o Athena cobra no mínimo 10 MB por consulta. A conta que importa é a de TB, no slide seguinte do deck.

**Pergunta para o grupo:** quem na empresa de vocês decide o formato dos arquivos do lake? E quem recebe a fatura de cada consulta?

**✅ Checkpoint:** o `qc lake compara` mostrou o mesmo resultado nas duas camadas, com o Parquet lendo muito menos?

---

## Lab 2 — Onde está a senha e o que chegou no banco (Bloco 2, ~25 min)

**Comando**

```bash
qc carga produtos
```

Ele roda o [`popular_produtos.py`](scripts/popular_produtos.py): lê a connection string do Secrets Manager, baixa o CSV do S3, cria a tabela `t_produtos` e grava os 20 produtos.

**Console**

1. **Secrets Manager → Secrets → `qc-aula02-xxxxxx/postgres`**. Em **Overview**, a pergunta não é a senha: é **quem pode lê-la** (a política). Em **Retrieve secret value**, veja o formato da connection string. É um lab descartável: a senha some no `terraform destroy`.
2. **RDS → Databases → `qc-aula02-xxxxxx` → Monitoring**: o pico de conexões na hora do script aparece com 1 a 2 minutos de atraso.

**No código, só vai o nome do segredo**

```bash
grep -n "SECRET_ID\|secretsmanager" ~/aie-cloud/aulas/02-storage-bancos/lab/scripts/popular_produtos.py
aws sts get-caller-identity --query Arn --output text   # quem está lendo o segredo
```

**O banco, em 3 consultas**

```bash
qc sql "SELECT COUNT(*) FROM t_produtos;"
qc sql "SELECT nome, preco FROM t_produtos ORDER BY preco DESC LIMIT 5;"
qc sql "SELECT categoria, COUNT(*) AS qtd, ROUND(AVG(preco), 2) AS preco_medio FROM t_produtos GROUP BY categoria;"
```

A última é a mesma do Athena no Lab 1: o resultado tem que bater. Aqui o dado foi convertido na gravação (preço em `NUMERIC`), o *schema-on-write*.

> Quer explorar à vontade? `qc sql` sem nada abre o banco no **pgcli** (sai com `\q`; se a tela parar em `(END)`, aperte `q`).

**Pergunta para o grupo:** se este script fosse para o GitHub, o que vazaria? E se a senha estivesse escrita nele, o que vocês teriam que fazer hoje à noite? *(Lembre do case Toyota.)*

**✅ Checkpoint:** o `qc sql` mostrou os 20 produtos e as mesmas categorias do Athena?

---

## Lab 3A — Reviews no DynamoDB, pelo console (Bloco 3, ~15 min)

**Comando**

```bash
qc carga reviews
```

**Console**

1. **DynamoDB → Tables → `qc-aula02-xxxxxx-reviews` → Explore table items**: os 30 itens, cada um com `produto_id` (chave de partição) e `review_id`.
2. **Opcional (para quem terminar antes): PartiQL editor** (menu à esquerda). O nome da tabela vai entre aspas duplas:

```sql
SELECT * FROM "qc-aula02-xxxxxx-reviews" WHERE produto_id = 5
```

**Pergunta para o grupo:** a consulta por produto é rápida porque `produto_id` é a chave. E "as 5 piores reviews da loja toda"? A tabela responde bem a essa pergunta? O que isso diz sobre escolher a chave antes de gravar?

**✅ Checkpoint:** os 30 itens apareceram no Explore table items, com `produto_id` e `review_id`?

---

## Lab 3B — O desafio da busca (Bloco 3, ~20 min)

**Comando**

```bash
qc indexa    # gera os embeddings dos 20 produtos e grava no pgvector (~1 min na 1ª vez)
```

**O desafio.** Cada grupo escreve três perguntas como um cliente faria, sem usar o nome do produto, e roda cada uma:

```bash
qc busca "algo para trabalhar em pé"
qc busca "presente para quem corre"
qc busca "<a pergunta do seu grupo>"
```

Cada resultado mostra, lado a lado, a busca por **palavra** (a frase no nome ou na descrição) e a busca pelo **sentido** (os 3 produtos com o embedding mais próximo). Anotem:

| Pergunta | A busca por palavra achou? | A busca pelo sentido acertou? | Algum resultado parecido, mas errado? |
|----------|----------------------------|-------------------------------|----------------------------------------|
| | | | |

**Pergunta para o grupo:** um agente usaria esse resultado para responder o cliente. O que acontece quando a busca traz um produto parecido, mas errado? Como vocês evitariam isso?

**✅ Checkpoint:** o grupo tem uma pergunta em que a busca pelo sentido errou?

---

## Sentimento das reviews: na Aula 4

A análise de sentimento das reviews (regra × IA) saiu desta aula: ela é o tema da Aula 4, de serviços cognitivos. O comando `qc sentimento` continua disponível para quem quiser testar as regras locais com as reviews do Lab 3A.

---

## Bloco 4 — A decisão (~60 min)

### Canvas de decisão, em grupo (~25 min)

Preencham o [canvas de decisão](../../../entregas/entrega-02/canvas-decisao.md), uma linha para cada um dos 9 domínios da QC, com custo pela [calculadora AWS](https://calculator.aws) (região `us-east-1`). Dois grupos apresentam, 5 minutos cada. O canvas é o **N2 da Entrega 02**.

### Um dado do seu trabalho (~5 min, individual)

Uma linha do mesmo canvas com um dado real do seu trabalho, anonimizado. Ela entra na reflexão da Entrega 02.

### Destroy (obrigatório)

```bash
# Sessão nova? source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh   (recupera a DB_PASSWORD)
cd ~/aie-cloud/aulas/02-storage-bancos/lab/terraform
terraform destroy -auto-approve -var="db_password=$DB_PASSWORD"
```

Leva ~5 min por causa do RDS. Depois, confira em **Resource Groups & Tag Editor → Tag Editor** (região `us-east-1`, tag `aula = 2`): a busca deve voltar vazia. **RDS esquecido ligado é o recurso mais caro desta aula.**

---

## As 5 perguntas para levar ao time

1. Onde mora o dado que o meu produto ou agente usa, e quem é o dono?
2. Quanto custa guardar esse dado por mês, e quanto ele cresce?
3. Esse dado pode ficar errado por um minuto, ou envolve dinheiro?
4. Onde está a senha desse banco, e quem consegue lê-la hoje?
5. O usuário procura por palavra exata ou pelo sentido?

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `qc: command not found` | O comando só existe depois do `source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh` |
| `ERRO: ... vazio. O terraform apply terminou?` | Espere o `apply` acabar e rode o `source` de novo; `qc status` mostra o que já existe |
| Timeout ao conectar no RDS | O IP do CloudShell mudou: o `source` mostra o `terraform apply` que libera o IP novo (~1 min) |
| `ExpiredToken` / `InvalidClientTokenId` | A sessão do Learner Lab acabou: **Start Lab** e CloudShell novo |
| `AccessDenied ... GetBucketObjectLockConfiguration` no `apply` | Código antigo: `git -C ~/aie-cloud pull`, `terraform init`, `terraform state rm aws_s3_bucket.qc`, `terraform apply` |
| `NoSuchKey` no `qc carga produtos` | O Lab 1 não rodou: `qc carga catalogo` |
| `qc busca` diz que `produtos_vetor` não existe | Rode antes `qc indexa` |
| Tela parada em `(END)` ou `:` no pgcli | Aperte `q`; use `LIMIT` |
| Athena: `datazone:ListDomains` | Use o link do editor clássico do Lab 1 |
| Athena: `No output location provided` | Troque o **Workgroup** (canto superior direito) para `qc-aula02-xxxxxx` |
| Athena: `Table already exists` | Siga para os `SELECT`; para recriar, `DROP TABLE qc.produtos;` |
| Athena volta 0 linhas | `LOCATION` com o bucket errado ou sem a `/` final |
| `qc lake cura`: `HIVE_PATH_ALREADY_EXISTS` ou `Table already exists` | Rode `qc lake cura` de novo: ele apaga a tabela e a pasta `curated/pedidos/` antes do CTAS |
| `qc lake cura`: "remove the 'external_location' property" | O workgroup está impondo o local de resultados. `git -C ~/aie-cloud pull` e `terraform apply` de novo (o workgroup do lab não impõe) |
| `qc lake compara`: `Table qc.pedidos_curated does not exist` | Faltou o `qc lake cura` |
| `pip` avisa que `aws-sam-cli requires click==8.1.8` | Algum `pip` rodou fora do venv: `pip install "click==8.1.8"` e rode o `source` de novo |
| `No space left on device` | `$HOME` de 1 GB cheio: `rm -rf ~/.cache/pip ~/.local/lib` (o `qc` instala tudo em `/tmp`) |

Mais casos e o passo a passo detalhado de cada banco: [guia de aprofundamento](guia-aprofundamento.md#troubleshooting--problemas-comuns).

---

## Referências

- [Amazon S3 — Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [Amazon Athena — editor de consultas](https://docs.aws.amazon.com/athena/latest/ug/querying-athena-tables.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [DynamoDB — PartiQL](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ql-gettingstarted.html)
- [pgvector](https://github.com/pgvector/pgvector)
