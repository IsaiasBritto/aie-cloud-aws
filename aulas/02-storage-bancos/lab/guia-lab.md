# Guia de Laboratório — Aula 2

**Tema:** Storage & Bancos de Dados na Nuvem
**Plataforma:** Amazon Web Services (AWS Academy Learner Lab)
**Ambiente:** **AWS CloudShell** — tudo no browser, sem instalar nada localmente
**Região:** `us-east-1`

---

## Visão geral do lab

```
Abertura    — fechar a Aula 1 (limpeza + Atividade 5 de Terraform)  ~20 min
Preparação  — terraform apply de TODA a camada de dados             ~10 min
Atividade 1 — S3: upload do CSV + SQL no arquivo com o Athena       ~20 min  (L₁)
Atividade 2 — RDS PostgreSQL + Secrets Manager + Python             ~25 min  (L₂)
Atividade 3 — DynamoDB + busca vetorial (pgvector)                  ~35 min  (L₃)
              Siga o produto 1 (o mesmo dado em cada banco)         ~10 min
Atividade 4 — Matriz de decisão de dados, em grupo                  ~15 min  (L₄)
Wrap-up     — terraform destroy + verificação de custo              ~10 min
```

Os tempos casam com o roteiro do deck (slide 2). Os blocos de teoria acontecem entre as atividades.

> **Regra de ouro:** sempre encerrar com `terraform destroy`.

### Por que `terraform apply` de uma vez só, antes das atividades?

A camada de dados da QC é uma **declaração única** — provisionar tudo de uma vez (~8 min, o RDS é o mais lento) reflete como IaC funciona na vida real. Enquanto o Terraform roda, você lê os arquivos `.tf` para entender o que está sendo construído.

---

## Pré-requisitos

- ✅ Aula 1 concluída (Learner Lab iniciado, CloudShell funcionando, Terraform instalado no `$HOME`)
- ✅ Esboço da arquitetura QC do grupo no repositório privado

---

## Abertura — fechar a Aula 1 (20 min)

**Parte A — Limpeza (~5 min).** A VM criada pelo console na Atividade 4 da Aula 1 pode estar parada, e o disco EBS continua cobrando.

1. Console **EC2** → **Instances** → filtre pela tag `aula = 1`
2. **Instance state → Terminate instance**
3. Depois que ela terminar: apague o security group criado pelo console e o Resource Group `rg-lab-aula01`

**Parte B — Terraform (~15 min).** Faça a [Atividade 5 do guia da Aula 1](../../01-fundamentos-iac/lab/guia-lab.md#atividade-5--terraform-recriar-a-mesma-ec2-via-iac): `init` → `plan` → `apply`, a demonstração de idempotência e o `terraform destroy`.

**✅ Checkpoint:** nenhuma EC2 com `aula = 1` na conta, e um `apply` + `destroy` feitos via Terraform?

---

## Preparação (15 min — antes do L₁)

### Passo 1 — Clone (ou atualize) o repositório e instale o Terraform

```bash
# Ainda não clonou? Clone:
cd ~ && git clone https://github.com/IsaiasBritto/aie-cloud-aws.git aie-cloud

# Já clonou na Aula 1? Atualize SEM apagar a pasta
# (apagar levaria junto o terraform.tfstate da Aula 1):
git -C ~/aie-cloud stash && git -C ~/aie-cloud pull

cd ~/aie-cloud/aulas/02-storage-bancos/lab/terraform

# Terraform no $HOME (só se ainda não instalou na Aula 1)
bash ~/aie-cloud/aulas/01-fundamentos-iac/lab/install_terraform.sh
export PATH="$HOME/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Pré-voo: a sessão tem acesso a S3, RDS, DynamoDB, e Secrets Manager?
bash ../check_regions.sh
```

> O `git stash` guarda as edições que você fez no `main.tf` da Aula 1 (a tag `ambiente`), para o `pull` não reclamar. Arquivos fora do Git, como o `terraform.tfstate`, ficam onde estão.

### Passo 2 — Provisione

```bash
# Senha do RDS — fica só na memória deste terminal (o RDS não aceita / @ " e espaço)
export DB_PASSWORD=$(openssl rand -hex 16)

terraform init
terraform apply -auto-approve -var="db_password=$DB_PASSWORD"
```

Enquanto o Terraform trabalha (~8 min), leia os arquivos:

| Arquivo | O que define |
|---------|--------------|
| [main.tf](terraform/main.tf) | Providers, sufixo aleatório, tags padrão, VPC padrão e o IP do CloudShell |
| [variables.tf](terraform/variables.tf) | `region` e `db_password` |
| [outputs.tf](terraform/outputs.tf) | Nomes e endpoints consumidos pelos scripts Python |
| [storage.tf](terraform/storage.tf) | Bucket S3 (pelo módulo [`modulos/bucket-s3`](../../../modulos/bucket-s3/main.tf), que usa a AWS CLI por causa de uma restrição do Learner Lab) + 3 prefixos (`catalogo/`, `imagens/`, `logs/`) + lifecycle |
| [rds.tf](terraform/rds.tf) | RDS PostgreSQL 16 `db.t3.micro` + security group (só o seu IP) |
| [secrets.tf](terraform/secrets.tf) | Secrets Manager: connection string do PostgreSQL |
| [dynamodb.tf](terraform/dynamodb.tf) | Tabela DynamoDB on-demand (`produto_id` + `review_id`) |
| [athena.tf](terraform/athena.tf) | Workgroup do Athena (resultados em `athena/` no bucket) e banco `qc` do Glue Data Catalog |

### Passo 3 — Carregue as variáveis da sessão

```bash
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
```

O [`exportar-outputs.sh`](exportar-outputs.sh) faz quatro coisas, e vale abrir o arquivo para ver como:

- lê os outputs do Terraform (`terraform output -raw bucket_name`, `secret_id`...) e exporta como variáveis: `BUCKET_NAME`, `SECRET_ID`, `DYNAMO_TABLE`, `DB_HOST`, `ATHENA_WORKGROUP`;
- cria e ativa um venv Python em `/tmp/venv-qc`, fora do `$HOME`, que tem só 1 GB. O Python do CloudShell já roda num virtualenv e recusa o `pip install --user`;
- cria o atalho **`qc_psql`**, que abre o PostgreSQL do RDS buscando a connection string no Secrets Manager na hora. A senha não aparece na tela nem fica guardada numa variável;
- avisa se o IP do CloudShell mudou desde o `apply` (o RDS só aceita o IP antigo) e mostra o comando que libera o novo.

> Use `source`, não `bash`: com `bash`, as variáveis e o atalho morrem junto com o processo.

### Se a sessão do CloudShell cair

O CloudShell encerra a sessão depois de ~20 min sem uso, e os blocos de teoria duram mais que isso. Variáveis, venv e atalho somem, mas o estado do Terraform fica no `$HOME`. Rode o mesmo `source` do Passo 3. Se aparecer `ModuleNotFoundError` ou `pgcli: command not found`, o `/tmp` foi limpo: refaça o `pip install` da atividade.

---

## Como estudar cada atividade: olhe antes, execute, olhe depois

Os scripts fazem o trabalho pesado, mas o objetivo é você entender **onde o dado está e em que forma**. Por isso cada atividade segue o mesmo ciclo:

1. **Antes:** abra o destino e veja como ele está, quase sempre vazio.
2. **Execute:** rode o script.
3. **Depois:** volte ao destino e encontre o dado que o script gravou.
4. **Responda:** as perguntas no fim de cada parte. Elas caem na entrega.

Ferramentas que você vai usar para olhar:

| Onde está o dado | Como olhar |
|---|---|
| Arquivo no S3 | Console do S3, AWS CLI e **Athena**: SQL direto sobre o arquivo, sem banco no meio |
| PostgreSQL no RDS | **`qc_psql`**, que abre o **pgcli**: cliente de terminal com autocompletar e resultado em tabela |
| DynamoDB | Console (**Explore table items**) e AWS CLI |

> **Por que não o "Query editor" do console do RDS?** Ele só funciona com Aurora e Data API, e a Data API exige classes de instância que o Learner Lab não libera. Para o banco, o caminho é um cliente: aqui, o pgcli no CloudShell.

---

## Atividade 1 — Bucket S3, o arquivo na origem (L₁)

### Passo 1 — Antes: o bucket recém-criado

No console: **S3** → bucket `qc-aula02-xxxxxx` → prefixos `catalogo/`, `imagens/`, `logs/`. Aba **Management**: a regra `logs-lifecycle` (Standard → Standard-IA em 30 dias → Glacier em 90 → expira em 365).

No terminal:

```bash
aws s3 ls "s3://$BUCKET_NAME" --recursive
```

Aparecem três "objetos" de 0 bytes, `catalogo/`, `imagens/` e `logs/`. No S3 não existe pasta: o Terraform criou objetos vazios com nome terminado em `/` só para o prefixo aparecer no console.

### Passo 2 — Execute: upload do CSV

```bash
# 1. O arquivo, ainda no CloudShell
head -5 ~/aie-cloud/aulas/02-storage-bancos/lab/data/produtos.csv

# 2. Quem está fazendo o upload? (no Learner Lab, a LabRole)
aws sts get-caller-identity

# 3. Upload para o prefixo catalogo/
aws s3 cp ~/aie-cloud/aulas/02-storage-bancos/lab/data/produtos.csv \
  "s3://$BUCKET_NAME/catalogo/produtos.csv"
```

### Passo 3 — Depois: o objeto no S3

**No console:** abra `catalogo/produtos.csv`. Na aba **Properties**, veja tamanho, classe de armazenamento (Standard), criptografia (SSE-S3) e **ETag**. O botão **Open** mostra o conteúdo.

**No terminal:**

```bash
# Metadados do objeto (a classe Standard aparece como null: é o padrão)
aws s3api head-object --bucket "$BUCKET_NAME" --key catalogo/produtos.csv \
  --query "{tamanho: ContentLength, tipo: ContentType, criptografia: ServerSideEncryption, etag: ETag}"

# O arquivo chegou íntegro? Num upload simples, o ETag é o MD5 do conteúdo
md5sum ~/aie-cloud/aulas/02-storage-bancos/lab/data/produtos.csv

# Ler o arquivo direto do S3, sem baixar para o disco
aws s3 cp "s3://$BUCKET_NAME/catalogo/produtos.csv" - | head -3
aws s3 cp "s3://$BUCKET_NAME/catalogo/produtos.csv" - | wc -l     # 21 = cabeçalho + 20 produtos
```

### Passo 4 — SQL sobre o arquivo, com o Athena

O Athena consulta arquivos no S3 com SQL. Você declara as colunas e o Athena lê o CSV na hora de cada consulta. O Terraform já criou o **workgroup** (onde ficam os resultados) e o banco **`qc`** do catálogo. A tabela, você escreve.

1. Com o Learner Lab aberto, entre direto no editor clássico por este link:
   **https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/query-editor**

   > Não entre pela página inicial do Athena: o botão de lá leva para o **SageMaker Unified Studio**, que depende do DataZone e dá `Access denied ... datazone:ListDomains` no Learner Lab.
2. No canto superior direito, em **Workgroup**, escolha `qc-aula02-xxxxxx` e confirme. Os resultados vão para `s3://<seu-bucket>/athena/`.
3. À esquerda: **Data source** `AwsDataCatalog`, **Database** `qc`.
4. Pegue o nome do seu bucket no terminal (`echo $BUCKET_NAME`), troque no SQL abaixo e clique em **Run**:

```sql
CREATE EXTERNAL TABLE qc.produtos (
  id        int,
  nome      string,
  descricao string,
  categoria string,
  preco     double,
  estoque   int
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://qc-aula02-xxxxxx/catalogo/'
TBLPROPERTIES ('skip.header.line.count' = '1');
```

5. Consulte o arquivo:

```sql
SELECT * FROM qc.produtos ORDER BY id LIMIT 5;

SELECT categoria, COUNT(*) AS qtd, ROUND(AVG(preco), 2) AS preco_medio
FROM qc.produtos
GROUP BY categoria
ORDER BY categoria;
```

> **Sem console?** O mesmo SQL roda no terminal com o atalho `qc_athena`, criado pelo `exportar-outputs.sh`. Ele já usa o seu workgroup e o banco `qc`, e o `$BUCKET_NAME` entra sozinho:
>
> ```bash
> qc_athena "CREATE EXTERNAL TABLE IF NOT EXISTS produtos (id int, nome string, descricao string, categoria string, preco double, estoque int) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' LOCATION 's3://$BUCKET_NAME/catalogo/' TBLPROPERTIES ('skip.header.line.count'='1')"
> qc_athena "SELECT categoria, COUNT(*) AS qtd, ROUND(AVG(preco),2) AS preco_medio FROM produtos GROUP BY categoria ORDER BY categoria"
> ```

Repare no **Data scanned** embaixo do resultado: o Athena cobra pelo volume lido (US$ 5 por TB). Aqui são ~2 KB.

> **Schema-on-read.** O `CREATE EXTERNAL TABLE` não copiou nem converteu nada: o arquivo no S3 continua sendo o mesmo CSV. A "tabela" é só uma definição guardada no **Glue Data Catalog** (console → AWS Glue → Data Catalog → Tables → `produtos`), aplicada a cada leitura. Na Atividade 2 você vai ver o oposto, *schema-on-write*.
>
> O `FIELDS TERMINATED BY ','` funciona porque nenhum campo deste CSV tem vírgula no meio. Um CSV com campos entre aspas e vírgulas internas pediria outro leitor (`OpenCSVSerde`).

### Passo 5 — Responda

1. O arquivo no S3 é igual ao do repositório? Como você provou isso?
2. Quem autorizou o upload? *(dica: a identidade do `get-caller-identity`, via política IAM. Não existe "chave do bucket": a permissão é sempre de uma identidade, e o CloudTrail registra qual identidade fez o quê.)*
3. Se alguém subir um segundo CSV em `catalogo/`, o que acontece com o `SELECT COUNT(*)` do Athena? Por quê?

**✅ Checkpoint L₁:** o `produtos.csv` está em `catalogo/` e o Athena devolveu as 6 categorias?

---

## Atividade 2 — RDS PostgreSQL + Secrets Manager + Python (L₂)

### Passo 1 — Antes: de onde vem a conexão

```bash
# Sempre antes do pip: ativa o venv de /tmp (e recupera variáveis e o qc_psql se a sessão caiu)
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
pip install --no-cache-dir boto3 "psycopg[binary]" pgcli

# A connection string que o script vai ler, com a senha escondida
aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text \
  | sed -E 's#(postgresql://[^:]+:)[^@]+@#\1*****@#'
```

Cada pedaço da connection string veio do Terraform:

| Pedaço | De onde veio |
|---|---|
| `qcadmin` | `username` no [`rds.tf`](terraform/rds.tf) |
| a senha (`*****`) | a `DB_PASSWORD` que você gerou com `openssl` na Preparação |
| o host `...rds.amazonaws.com:5432` | o endereço do RDS, criado pelo `apply` |
| `/qcdb` | `db_name` no `rds.tf` |
| `?sslmode=require` | montado no [`secrets.tf`](terraform/secrets.tf): a conexão só sobe criptografada |

> No console, o segredo fica em **Secrets Manager → Secrets → `qc-aula02-xxxxxx/postgres` → Retrieve secret value**. Lá a senha aparece aberta: não projete essa tela.

### Passo 2 — Antes: o que o script vai criar

```bash
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
head -2 ../data/produtos.csv
grep -A8 "CREATE TABLE" popular_produtos.py
```

No CSV tudo é texto. Na tabela, cada coluna tem tipo: `preco` vira `NUMERIC(10,2)`, com duas casas exatas, e `estoque` vira `INTEGER`. Isso é **schema-on-write**: o banco define o formato antes e recusa o que não couber. No Athena (Atividade 1), o esquema foi aplicado na leitura, sobre o arquivo como ele está.

### Passo 3 — Execute: o script de carga

O [`popular_produtos.py`](scripts/popular_produtos.py): lê a connection string do Secrets Manager → baixa o CSV do S3 → conecta no RDS via `psycopg` → cria `t_produtos` (drop se existir) → insere os 20 produtos.

```bash
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 popular_produtos.py
```

Saída esperada: `✓ 20 produtos inseridos` e o top 3 mais caros.

> **Erro comum — `connection timeout`:** o IP do CloudShell mudou desde o apply. Rode o `source` do `exportar-outputs.sh`: ele confirma a troca de IP e mostra o `apply` que libera o novo.

### Passo 4 — Depois: os dados no banco

```bash
qc_psql
```

```sql
\d t_produtos
SELECT COUNT(*) FROM t_produtos;
SELECT * FROM t_produtos ORDER BY id LIMIT 5;

SELECT categoria, COUNT(*) AS qtd, ROUND(AVG(preco), 2) AS preco_medio
FROM t_produtos
GROUP BY categoria
ORDER BY categoria;
```

A última consulta é a mesma que você rodou no Athena. O resultado tem que bater. Para sair do pgcli, `\q`.

> Se o resultado for grande, o pgcli abre um paginador e aparece `(END)` ou `:` no canto da tela. Aperte **`q`** para voltar ao prompt.

**No console do RDS**, aba **Monitoring**: os gráficos **DB Connections** e **Write IOPS** mostram o pico na hora em que o script rodou. As métricas chegam com 1 ou 2 minutos de atraso.

> O `\d t_produtos` confirma o que você leu no `CREATE TABLE` do Passo 2: o dado foi convertido na gravação. No Athena, o mesmo preço é um `double`, lido do texto a cada consulta.

### Passo 5 — Responda

1. No Athena o preço é `double`; no RDS, `NUMERIC(10,2)`. Por que essa diferença importa quando o dado é dinheiro?
2. O que aconteceria se a connection string viesse escrita no `popular_produtos.py` e o arquivo fosse commitado num repositório público?
3. Como você protegeria esse segredo num agente rodando numa AWS Lambda? *(dica: a função lê o segredo em runtime com a execution role, e o Secrets Manager pode rotacionar a senha sozinho)*
4. Por que o `boto3` "simplesmente funciona" no CloudShell, sem chave? De onde vem a credencial? E no seu notebook?

**✅ Checkpoint L₂:** a consulta por categoria deu o mesmo resultado no Athena e no RDS?

---

## Atividade 3 — DynamoDB + busca vetorial (L₃)

### Parte A — DynamoDB (15 min)

**Conferir:** console **DynamoDB** → Tables → `qc-aula02-xxxxxx-reviews` → chave de partição `produto_id` (Number) e de ordenação `review_id` (String). Capacidade **On-demand**.

**Antes:**

```bash
aws dynamodb scan --table-name "$DYNAMO_TABLE" --select COUNT --query "{itens: Count}"
```

Zero itens. No console, **Explore table items** mostra a tabela vazia.

> Não confie no `ItemCount` do console ou do `describe-table` para isso: a AWS só atualiza esse número a cada ~6 horas.

**Execute:** o [`popular_reviews.py`](scripts/popular_reviews.py) insere 30 reviews com `batch_writer` e faz uma **Query** na partição `produto_id = 5`, filtrando `score >= 4`.

```bash
# Sempre antes do pip: ativa o venv de /tmp (e recupera variáveis e o qc_psql se a sessão caiu)
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 popular_reviews.py
```

**Depois:**

```bash
# Um item como o DynamoDB guarda: cada atributo leva o tipo (N = número, S = texto)
aws dynamodb query --table-name "$DYNAMO_TABLE" \
  --key-condition-expression "produto_id = :p" \
  --expression-attribute-values '{":p": {"N": "5"}}' \
  --query "Items[0]"

# A mesma pergunta de dois jeitos: Query (uma partição) × Scan (a tabela inteira)
aws dynamodb query --table-name "$DYNAMO_TABLE" \
  --key-condition-expression "produto_id = :p" \
  --expression-attribute-values '{":p": {"N": "5"}}' \
  --return-consumed-capacity TOTAL \
  --query "{devolvidos: Count, lidos: ScannedCount, capacidade: ConsumedCapacity.CapacityUnits}"

aws dynamodb scan --table-name "$DYNAMO_TABLE" \
  --filter-expression "produto_id = :p" \
  --expression-attribute-values '{":p": {"N": "5"}}' \
  --return-consumed-capacity TOTAL \
  --query "{devolvidos: Count, lidos: ScannedCount, capacidade: ConsumedCapacity.CapacityUnits}"
```

Os dois devolvem os mesmos itens, mas o Scan **leu** os 30. Com 30 itens a capacidade cobrada quase não muda; com 30 milhões, o Scan leria (e cobraria) 30 milhões.

**No console:** a tabela → **Explore table items** → abra um item e veja o JSON. Depois faça uma **Query** com `produto_id = 5` e compare com um **Scan**.

**Responda:**

1. Os itens têm exatamente os mesmos atributos? O que o DynamoDB faria se um item novo chegasse com um atributo a mais?
2. Por que o `ScannedCount` do Scan é 30 e o da Query é bem menor?
3. Que pergunta de negócio essa tabela **não** responde bem? *(pense em "todas as reviews de um cliente")*

### Parte B — Busca vetorial com pgvector (20 min)

O mesmo RDS da Atividade 2 vira um Vector DB com a extensão **pgvector**.

**Antes:**

```bash
qc_psql
```

```sql
\dx
SELECT name, default_version, installed_version
FROM pg_available_extensions WHERE name = 'vector';
\dt

-- Busca por palavra: a frase não existe em nenhuma descrição
SELECT nome FROM t_produtos WHERE descricao ILIKE '%trabalhar em pé%';
-- Só acha quando você acerta as palavras exatas
SELECT nome FROM t_produtos WHERE descricao ILIKE '%em pé%';
```

A extensão `vector` está disponível no RDS, mas não instalada (`installed_version` vazio), e só existe a `t_produtos`. Saia com `\q`.

**Execute:** o [`indexar_produtos.py`](scripts/indexar_produtos.py):

1. Cria a extensão `vector`, a tabela `produtos_vetor` e um índice **HNSW**
2. Baixa o CSV do S3
3. Gera os embeddings (MiniLM multilíngue, 384 dimensões) **aqui no CloudShell** e grava cada produto já com o seu vetor
4. Demonstra busca por palavra × busca por significado × filtro + vetor

```bash
# Sempre antes do pip: ativa o venv de /tmp (e recupera variáveis e o qc_psql se a sessão caiu)
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
pip install --no-cache-dir pgvector fastembed
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 indexar_produtos.py
```

Na primeira execução o modelo (~220 MB) é baixado para o `/tmp` (o `$HOME` do CloudShell tem só 1 GB).

> **Por que embedding local e não um serviço?** O Learner Lab não libera o Amazon Bedrock. Em produção, o modelo de embedding seria do Bedrock (Titan/Cohere), ou o **Bedrock Knowledge Bases** faria chunking, embeddings e índice de uma vez.

**Depois:**

```bash
qc_psql
```

```sql
\dx
\d produtos_vetor

-- O "significado" de cada produto é uma lista de 384 números
SELECT id, nome, vector_dims(embedding) AS dims,
       (embedding::real[])[1:5] AS primeiros_5
FROM produtos_vetor ORDER BY id LIMIT 3;

-- Quanto espaço os vetores ocupam
SELECT pg_size_pretty(pg_total_relation_size('t_produtos'))     AS t_produtos,
       pg_size_pretty(pg_total_relation_size('produtos_vetor')) AS produtos_vetor;

-- Os 3 produtos mais parecidos com a cadeira ergonômica (id 1)
SELECT b.nome AS parecido,
       ROUND((1 - (a.embedding <=> b.embedding))::numeric, 2) AS similaridade
FROM produtos_vetor a JOIN produtos_vetor b ON a.id <> b.id
WHERE a.id = 1
ORDER BY a.embedding <=> b.embedding
LIMIT 3;
```

**Responda:**

1. O que significa o 3º número do vetor da cadeira, sozinho? *(nada: o significado está na posição do vetor inteiro em relação aos outros)*
2. Por que a `produtos_vetor` ocupa bem mais espaço que a `t_produtos`, com os mesmos 20 produtos?
3. A busca por `'%em pé%'` achou a mesa; a por `'%trabalhar em pé%'`, não. A vetorial achou com a frase inteira. O que isso diz sobre o tipo de pergunta que um agente recebe?

### Parte C — Siga o produto 1 (10 min)

O mesmo produto agora existe em vários lugares, cada um numa forma diferente. Encontre-o em todos:

| Onde | Como olhar |
|---|---|
| CSV no CloudShell | `grep '^1,' ~/aie-cloud/aulas/02-storage-bancos/lab/data/produtos.csv` |
| Objeto no S3 | `aws s3 cp "s3://$BUCKET_NAME/catalogo/produtos.csv" - \| grep '^1,'` |
| Athena (sobre o S3) | `SELECT * FROM qc.produtos WHERE id = 1;` |
| RDS, tabela transacional | no `qc_psql`: `SELECT * FROM t_produtos WHERE id = 1;` |
| RDS, tabela vetorial | no `qc_psql`: `SELECT id, nome, vector_dims(embedding) FROM produtos_vetor WHERE id = 1;` |
| DynamoDB, reviews | `aws dynamodb query --table-name "$DYNAMO_TABLE" --key-condition-expression "produto_id = :p" --expression-attribute-values '{":p": {"N": "1"}}' --query "Items[].texto.S"` |

> As reviews são sorteadas entre os 20 produtos: o produto 1 pode ter várias ou nenhuma. Se vier vazio, troque o `1` por outro id.

**Responda (em grupo):**

1. Qual dessas cópias é a **fonte da verdade** do produto? Por quê?
2. Se o preço da cadeira mudar no RDS, quais cópias ficam desatualizadas? Quem deveria atualizá-las?
3. Por que a QC precisa de tantas formas do mesmo dado? Para cada uma, diga que pergunta ela responde melhor.

**✅ Checkpoint L₃:** reviews no DynamoDB, a busca "algo para trabalhar em pé" trouxe a mesa de escritório sem nenhuma palavra em comum, e o grupo respondeu a Parte C?

---

## Atividade 4 — Matriz de decisão de dados, em grupo (L₄)

**Objetivo:** sair da execução e ir para a decisão — a competência que o MBA cobra.

Partindo das 4 decisões de hoje (catálogo → RDS, reviews → DynamoDB, imagens e logs → S3 com lifecycle, busca semântica → pgvector), completem a matriz para os **9 domínios do [Exercício 2.1](../exercicios.md)**:

| Domínio da QC | Serviço AWS | Por quê | O que vocês **não** usariam, e por quê |
|---------------|-------------|---------|----------------------------------------|
| ... | ... | ... | ... |

Nos últimos minutos, dois grupos defendem uma escolha em voz alta. O resultado é o ponto de partida do **N2 da entrega 02**.

**✅ Checkpoint L₄:** a matriz tem a coluna do "não usaríamos" preenchida?

---

## Wrap-up — Destroy e custo zero (10 min)

```bash
# Perdeu a sessão? O script recupera a DB_PASSWORD do Secrets Manager:
# source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
cd ~/aie-cloud/aulas/02-storage-bancos/lab/terraform
terraform destroy -auto-approve -var="db_password=$DB_PASSWORD"
```

O destroy apaga bucket (mesmo com objetos: o módulo `modulos/bucket-s3` esvazia antes de apagar), RDS (sem snapshot final), segredos (sem janela de recuperação), tabela DynamoDB, workgroup do Athena e o banco `qc` do Glue, com a tabela que você criou. Leva ~5 min por causa do RDS.

**Conferir:**
- **Resource Groups & Tag Editor → Tag Editor** → região `us-east-1`, tipo *All supported resource types*, tag `aula = 2` → a busca deve voltar **vazia**
- Página do Learner Lab → crédito consumido

**RDS esquecido ligado é o recurso mais caro desta aula.**

---

## Conexão com o projeto Quantum Commerce

```
infrastructure/
  ├── main.tf, variables.tf, outputs.tf
  ├── storage.tf    (S3: catálogo, imagens, logs + lifecycle)
  ├── rds.tf        (t_produtos — transacional; produtos_vetor — pgvector)
  ├── secrets.tf    (Secrets Manager)
  ├── dynamodb.tf   (reviews — NoSQL)
  └── athena.tf     (SQL sobre o S3 — schema-on-read)
```

- **Aula 3** — a Lambda lê o catálogo do S3
- **Aula 4** — serviços de IA analisam reviews e imagens do bucket
- **Aula 5** — agentes usam o catálogo e a busca vetorial como ferramentas

---

## Troubleshooting — Problemas comuns

| Problema | Causa | Solução |
|----------|-------|---------|
| `AccessDenied ... GetBucketObjectLockConfiguration` no `terraform apply` | O Learner Lab bloqueia essa leitura, que o `aws_s3_bucket` faz sempre. Os labs agora criam o bucket pelo módulo `modulos/bucket-s3` (AWS CLI) | `git -C ~/aie-cloud pull`, `terraform init`, `terraform state rm aws_s3_bucket.qc` e `terraform apply` de novo. O módulo reaproveita o bucket que já foi criado |
| `ExpiredToken` / `InvalidClientTokenId` | Sessão do Learner Lab acabou | **Start Lab** de novo e abra um CloudShell novo |
| `InvalidParameterValue: The parameter MasterUserPassword...` | Senha com `/ @ "` ou espaço | `export DB_PASSWORD=$(openssl rand -hex 16)` |
| Python: `connection timeout` no RDS | IP do CloudShell mudou | `source ../exportar-outputs.sh` (na pasta `scripts`) mostra o `apply` que libera o novo IP |
| `AccessDenied` ao criar recurso | Serviço/tipo fora do que o Learner Lab libera | Confira `bash ../check_regions.sh`; use `us-east-1` |
| `NoSuchKey` no script | O upload da Atividade 1 não aconteceu | Refaça o `aws s3 cp` e confira com `aws s3 ls` |
| `ResourceNotFoundException` no Secrets Manager | `SECRET_ID` vazio ou de outro apply | `source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh` |
| `pip` avisa que `aws-sam-cli requires click==8.1.8` | O `pip install` rodou fora do venv e mexeu no Python do próprio CloudShell | `pip uninstall -y pgcli pgspecial cli_helpers psycopg` e `pip install "click==8.1.8"`; depois rode o `source` do `exportar-outputs.sh` e repita o `pip install` |
| `qc_psql: command not found` | O atalho só existe depois do `source` | `source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh` |
| `qc_psql` diz "Instale um cliente" | O pgcli não está no venv (o `/tmp` foi limpo) | `pip install --no-cache-dir pgcli` |
| A tela mostra `(END)` ou `:` e não aceita comandos | O pgcli abriu o paginador para um resultado grande | Aperte `q`; use `LIMIT` nas consultas |
| Athena: `Access denied ... datazone:ListDomains` | Você entrou pela página inicial do Athena, que leva ao SageMaker Unified Studio | Use o link direto do editor clássico (Atividade 1, Passo 4), ou o atalho `qc_athena` no terminal |
| Athena: `Table already exists` | O `CREATE EXTERNAL TABLE` já rodou | Siga para os `SELECT`; para recriar, `DROP TABLE qc.produtos;` antes |
| Athena: `No output location provided` | Workgroup errado selecionado (`primary`) | No canto superior direito, troque o **Workgroup** para `qc-aula02-xxxxxx` |
| Athena volta 0 linhas | `LOCATION` com o nome do bucket errado ou sem a barra final | Confira com `echo $BUCKET_NAME`; o caminho termina em `/catalogo/` |
| `extension "vector" is not available` | Versão do PostgreSQL sem pgvector | O lab usa PostgreSQL 16 (com pgvector). Confira `engine_version` em `rds.tf` |
| `No space left on device` no CloudShell | `$HOME` de 1 GB cheio (providers, pip) | instale os pacotes no venv de `/tmp/venv-qc`, nunca no `$HOME`; `rm -rf ~/.cache/pip ~/.local/lib`; confira com `du -sh ~/.local ~/.cache ~/.terraform.d` e use o `TF_PLUGIN_CACHE_DIR` |
| `ModuleNotFoundError` no Python | O venv de `/tmp` não está ativo ou foi apagado (a sessão reiniciou) | `python3 -m venv /tmp/venv-qc && source /tmp/venv-qc/bin/activate` e rode o `pip install` da atividade de novo |
| `Can not perform a '--user' install` no `pip` | O Python do CloudShell já roda num virtualenv | Use o venv: `python3 -m venv /tmp/venv-qc && source /tmp/venv-qc/bin/activate` e `pip install` **sem** `--user` |
| `BucketAlreadyExists` | Nome global de bucket | O sufixo aleatório evita; rode `terraform apply` de novo |

---

## Tarefa pós-aula

1. Atualizar o diagrama da arquitetura QC (camada de dados detalhada)
2. Responder as 3 perguntas da L₂ (Secrets Manager) e levar a matriz da L₄ para o Exercício 2.1
3. Resolver pelo menos o Nível 1 de [exercicios.md](../exercicios.md)

---

## Referências

- [Amazon S3 — Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [Amazon RDS for PostgreSQL — extensões (pgvector)](https://docs.aws.amazon.com/AmazonRDS/latest/PostgreSQLReleaseNotes/postgresql-extensions.html)
- [pgvector](https://github.com/pgvector/pgvector)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)
- [Amazon DynamoDB — boas práticas de chave de partição](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-design.html)
- [Credenciais do boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/credentials.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
