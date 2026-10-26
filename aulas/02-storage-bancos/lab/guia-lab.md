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
Atividade 1 — Bucket S3 + upload do CSV do catálogo                 ~10 min  (L₁)
Atividade 2 — RDS PostgreSQL + Secrets Manager + Python             ~15 min  (L₂)
Atividade 3 — DynamoDB + busca vetorial (pgvector)                  ~35 min  (L₃)
              MongoDB na EC2 (Parte C)                              demo do professor
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

# Pré-voo: a sessão tem acesso a S3, RDS, DynamoDB, Secrets Manager e EC2?
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

> **Professor (demo do MongoDB):** rode `export TF_VAR_criar_mongo=true` **antes** do `apply`. A variável fica valendo para todos os comandos seguintes no terminal; sem ela, um `apply` posterior apagaria a EC2 do Mongo. Os alunos não precisam do Mongo.

Enquanto o Terraform trabalha (~8 min), leia os arquivos:

| Arquivo | O que define |
|---------|--------------|
| [main.tf](terraform/main.tf) | Providers, sufixo aleatório, tags padrão, VPC padrão e o IP do CloudShell |
| [variables.tf](terraform/variables.tf) | `region`, `db_password` e as senhas do MongoDB |
| [outputs.tf](terraform/outputs.tf) | Nomes e endpoints consumidos pelos scripts Python |
| [storage.tf](terraform/storage.tf) | Bucket S3 (pelo módulo [`modulos/bucket-s3`](../../../modulos/bucket-s3/main.tf), que usa a AWS CLI por causa de uma restrição do Learner Lab) + 3 prefixos (`catalogo/`, `imagens/`, `logs/`) + lifecycle |
| [rds.tf](terraform/rds.tf) | RDS PostgreSQL 16 `db.t3.micro` + security group (só o seu IP) |
| [secrets.tf](terraform/secrets.tf) | Secrets Manager: connection string do PostgreSQL e credenciais do Mongo |
| [dynamodb.tf](terraform/dynamodb.tf) | Tabela DynamoDB on-demand (`produto_id` + `review_id`) |
| [mongo.tf](terraform/mongo.tf) | EC2 com Docker: MongoDB 7.0 + Mongo Express (Lab 3C, só com `criar_mongo = true`) |

### Passo 3 — Exporte os outputs

```bash
# Armazena em variáveis valores criados pelo terraform
export BUCKET_NAME=$(terraform output -raw bucket_name)
export SECRET_ID=$(terraform output -raw secret_id)
export DYNAMO_TABLE=$(terraform output -raw dynamodb_table)
export DB_HOST=$(terraform output -raw db_endpoint)

# Pacotes Python fora do $HOME (que tem só 1 GB): pip install --user grava em /tmp/pyuser
export PYTHONUSERBASE=/tmp/pyuser

# Exibe em tela
echo "Bucket: $BUCKET_NAME"
echo "Secret: $SECRET_ID"
echo "DynamoDB: $DYNAMO_TABLE"
echo "RDS: $DB_HOST"
```

### Se a sessão do CloudShell cair

O CloudShell encerra a sessão depois de ~20 min sem uso — e os blocos de teoria duram mais que isso. As variáveis somem, mas o estado do Terraform fica no `$HOME`. Um comando recupera tudo:

```bash
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
```

O [`exportar-outputs.sh`](exportar-outputs.sh) exporta os outputs, recupera a `DB_PASSWORD` do Secrets Manager, aponta o `PYTHONUSERBASE` para `/tmp/pyuser` e **avisa se o IP do CloudShell mudou** — nesse caso, ele mostra o `terraform apply` que libera o novo IP no RDS.

> Use `source`, não `bash`: com `bash`, as variáveis morrem junto com o processo. Os pacotes do `pip` ficam em `/tmp`, que é limpo quando a sessão reinicia: se der `ModuleNotFoundError`, rode o `pip install` da atividade de novo.

---

## Atividade 1 — Bucket S3 + upload do CSV (L₁)

### Passo 1 — Conferir o que foi provisionado

No console: **S3** → bucket `qc-aula02-xxxxxx` → prefixos `catalogo/`, `imagens/`, `logs/`. Aba **Management**: a regra `logs-lifecycle` (Standard → Standard-IA em 30 dias → Glacier em 90 → expira em 365).

### Passo 2 — Upload do CSV de produtos

```bash
# 1. Localize e explore o arquivo
ls ~/aie-cloud/aulas/02-storage-bancos/lab/data/
head -5 ~/aie-cloud/aulas/02-storage-bancos/lab/data/produtos.csv

# 2. Confira a identidade (no Learner Lab, a LabRole já acessa o S3)
aws sts get-caller-identity

# 3. Upload para o prefixo catalogo/
aws s3 cp ~/aie-cloud/aulas/02-storage-bancos/lab/data/produtos.csv \
  s3://$BUCKET_NAME/catalogo/produtos.csv

# 4. Confirme
aws s3 ls s3://$BUCKET_NAME/catalogo/
```

> **Para discutir:** quem autorizou o upload? A **LabRole** da sua sessão, via política IAM. Não existe "chave do bucket" que dê acesso total a quem a tiver — a permissão é sempre de uma identidade, e o CloudTrail registra qual identidade fez o quê.

**✅ Checkpoint L₁:** `produtos.csv` aparece em `catalogo/`?

---

## Atividade 2 — RDS PostgreSQL + Secrets Manager + Python (L₂)

### Passo 1 — Conferir o que foi provisionado

- **RDS** → Databases → `qc-aula02-xxxxxx` (PostgreSQL 16, `db.t3.micro`). Aba **Connectivity & security**: o security group só aceita a porta 5432 do IP do seu CloudShell.
- **Secrets Manager** → `qc-aula02-xxxxxx/postgres`. Clique em **Retrieve secret value** só para ver o formato — o script nunca imprime isso.

### Passo 2 — Rodar o script

O [`popular_produtos.py`](scripts/popular_produtos.py): lê a connection string do Secrets Manager → baixa o CSV do S3 → conecta no RDS via `psycopg` → cria `t_produtos` (drop se existir) → insere os 20 produtos.

```bash
# Perdeu a sessão? source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
export PYTHONUSERBASE=/tmp/pyuser
pip install --user --no-cache-dir boto3 "psycopg[binary]"
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 popular_produtos.py
```

Saída esperada: `✓ 20 produtos inseridos` e o top 3 mais caros.

> **Erro comum — `connection timeout`:** o IP do CloudShell mudou desde o apply. Rode `source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh`: ele confirma a troca de IP e mostra o `apply` que libera o novo.

### Passo 3 — Consultar pelo psql (opcional)

```bash
sudo dnf install -y postgresql16 >/dev/null 2>&1 || sudo dnf install -y postgresql15
psql "$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text)" \
  -c "SELECT categoria, COUNT(*), ROUND(AVG(preco),2) FROM t_produtos GROUP BY categoria;"
```

**✅ Checkpoint L₂:** você inseriu 20 produtos no RDS **lendo o segredo do Secrets Manager**?

### Passo 4 — Discussão (3 min)

1. O que aconteceria se a `conn_str` viesse hardcoded no `popular_produtos.py` e o arquivo fosse commitado num repo público?
2. Como você protegeria esse segredo se ele fosse usado por um agente rodando numa AWS Lambda? *(dica: a função lê o segredo em runtime com a execution role — e o Secrets Manager pode rotacionar a senha sozinho)*
3. Por que o `boto3` "simplesmente funciona" no CloudShell, sem chave? De onde vem a credencial? E no seu notebook?

---

## Atividade 3 — DynamoDB / MongoDB + busca vetorial (L₃)

### Parte A — DynamoDB (15 min)

**Conferir:** console **DynamoDB** → Tables → `qc-aula02-xxxxxx-reviews` → chave de partição `produto_id` (Number) e de ordenação `review_id` (String). Capacidade **On-demand**.

O [`popular_reviews.py`](scripts/popular_reviews.py) insere 30 reviews com `batch_writer` e faz uma **Query** na partição `produto_id = 5` filtrando `score >= 4`.

```bash
# Perdeu a sessão? source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
export PYTHONUSERBASE=/tmp/pyuser
pip install --user --no-cache-dir boto3
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 popular_reviews.py
```

**Explorar no console:** a tabela → **Explore table items** → **Query** com `produto_id = 5`. Compare com **Scan**: a Query lê uma partição; o Scan lê a tabela inteira (e cobra por isso).

### Parte B — Busca vetorial com pgvector (20 min)

O mesmo RDS da Atividade 2 vira um Vector DB com a extensão **pgvector**. O [`indexar_produtos.py`](scripts/indexar_produtos.py):

1. Cria a extensão `vector`, a tabela `produtos_vetor` e um índice **HNSW**
2. Baixa o CSV do S3
3. Gera os embeddings (MiniLM multilíngue, 384 dimensões) **aqui no CloudShell** e grava cada produto já com o seu vetor
4. Demonstra busca por palavra × busca por significado × filtro + vetor

```bash
# Perdeu a sessão? source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
export PYTHONUSERBASE=/tmp/pyuser
pip install --user --no-cache-dir boto3 "psycopg[binary]" pgvector fastembed
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 indexar_produtos.py
```

Na primeira execução o modelo (~220 MB) é baixado para o `/tmp` (o `$HOME` do CloudShell tem só 1 GB).

> **Por que embedding local e não um serviço?** O Learner Lab não libera o Amazon Bedrock. Em produção, o modelo de embedding seria do Bedrock (Titan/Cohere) — ou o **Bedrock Knowledge Bases** faria chunking, embeddings e índice de uma vez.

**Busca no psql (opcional):**

```bash
psql "$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text)" \
  -c "SELECT a.nome, b.nome AS parecido, ROUND((1 - (a.embedding <=> b.embedding))::numeric, 2) AS similaridade
      FROM produtos_vetor a JOIN produtos_vetor b ON a.id <> b.id
      WHERE a.id = 1 ORDER BY a.embedding <=> b.embedding LIMIT 3;"
```

### Parte C — MongoDB na EC2 (demo do professor)

> **Opcional para o aluno.** O ponto aqui não é aprender MongoDB, e sim a decisão **gerenciado (DynamoDB) × autogerenciado (Mongo numa EC2)**: patch, backup, alta disponibilidade e portas passam a ser problema seu. Na AWS, o Mongo gerenciado seria o **Amazon DocumentDB**.

A EC2 só existe se o `apply` rodou com `export TF_VAR_criar_mongo=true` (ver Preparação). Ela sobe o MongoDB 7.0 e o Mongo Express em Docker (~2 min após o apply).

```bash
# Com TF_VAR_criar_mongo=true já exportado no terminal:
terraform -chdir="$HOME/aie-cloud/aulas/02-storage-bancos/lab/terraform" apply -auto-approve -var="db_password=$DB_PASSWORD"
source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh   # exporta MONGO_IP e MONGO_SECRET_ID

export PYTHONUSERBASE=/tmp/pyuser
pip install --user --no-cache-dir boto3 pymongo
cd ~/aie-cloud/aulas/02-storage-bancos/lab/scripts
python3 popular_reviews_mongo.py
```

O script lê usuário e senha do **Secrets Manager** — o mesmo padrão do RDS.

**Explorar no Mongo Express:** abra `$(terraform output -raw mongo_express_url)` no navegador (usuário `qcadmin`, senha `QCview2024!`) → `qc-db` → `reviews`.

> **Para discutir:** a porta 27017 só aceita o IP do CloudShell, mas a 8081 está aberta para a internet (com senha). Por que essa diferença? O que mudaria em produção?

**✅ Checkpoint L₃:** reviews no DynamoDB e a busca "algo para trabalhar em pé" trouxe a mesa de escritório sem nenhuma palavra em comum?

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

O destroy apaga bucket (mesmo com objetos: o módulo `modulos/bucket-s3` esvazia antes de apagar), RDS (sem snapshot final), segredos (sem janela de recuperação), tabela DynamoDB e, se foi criada, a EC2 do Mongo. Leva ~5 min por causa do RDS.

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
  └── mongo.tf      (reviews — MongoDB na EC2, opcional: criar_mongo = true)
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
| Python: `connection timeout` no RDS ou no Mongo | IP do CloudShell mudou | `source ../exportar-outputs.sh` (na pasta `scripts`) mostra o `apply` que libera o novo IP |
| `AccessDenied` ao criar recurso | Serviço/tipo fora do que o Learner Lab libera | Confira `bash ../check_regions.sh`; use `us-east-1` |
| `NoSuchKey` no script | O upload da Atividade 1 não aconteceu | Refaça o `aws s3 cp` e confira com `aws s3 ls` |
| `ResourceNotFoundException` no Secrets Manager | `SECRET_ID` vazio ou de outro apply | `source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh` |
| `extension "vector" is not available` | Versão do PostgreSQL sem pgvector | O lab usa PostgreSQL 16 (com pgvector). Confira `engine_version` em `rds.tf` |
| `No space left on device` no CloudShell | `$HOME` de 1 GB cheio (providers, pip) | `export PYTHONUSERBASE=/tmp/pyuser` antes do `pip`; `rm -rf ~/.cache/pip ~/.local/lib`; confira com `du -sh ~/.local ~/.cache ~/.terraform.d` e use o `TF_PLUGIN_CACHE_DIR` |
| `ModuleNotFoundError` no Python | `/tmp/pyuser` foi limpo (sessão reiniciou) ou faltou o `PYTHONUSERBASE` | `export PYTHONUSERBASE=/tmp/pyuser` e rode o `pip install` da atividade de novo |
| Script do Mongo: `MONGO_IP vazio` | O MongoDB é opcional e não foi criado | É demo do professor: `export TF_VAR_criar_mongo=true` e `apply` |
| MongoDB: `ServerSelectionTimeoutError` | EC2 ainda subindo os containers | Aguarde 2 min e rode de novo. Log: EC2 → Actions → Monitor → Get system log |
| Mongo Express pede senha | Basic auth ligado de propósito | Usuário `qcadmin`, senha `QCview2024!` |
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
