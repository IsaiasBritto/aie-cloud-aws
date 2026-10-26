# Terraform — Aula 2 (camada de dados da QC)

Provisiona, num único `apply`, a camada de dados da Quantum Commerce na AWS:

| Arquivo | Recurso |
|---------|---------|
| [main.tf](main.tf) | Providers (aws, random, http), sufixo aleatório, `default_tags`, VPC padrão e IP do CloudShell |
| [variables.tf](variables.tf) | `region` e `db_password` (obrigatória) |
| [storage.tf](storage.tf) | Bucket S3 privado e criptografado + prefixos `catalogo/`, `imagens/`, `logs/` + lifecycle dos logs |
| [rds.tf](rds.tf) | RDS PostgreSQL 16 `db.t3.micro` (pgvector disponível) + security group só para o seu IP |
| [secrets.tf](secrets.tf) | Secrets Manager: connection string do PostgreSQL |
| [dynamodb.tf](dynamodb.tf) | Tabela on-demand `reviews` (partição `produto_id`, ordenação `review_id`) |
| [outputs.tf](outputs.tf) | `bucket_name`, `secret_id`, `dynamodb_table`, `db_endpoint`, `meu_ip` |

## Como usar (AWS CloudShell, Learner Lab iniciado)

```bash
cd ~/aie-cloud/aulas/02-storage-bancos/lab/terraform
export PATH="$HOME/bin:$PATH" TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

export DB_PASSWORD=$(openssl rand -hex 16)   # RDS não aceita / @ " e espaço
terraform init
terraform apply -auto-approve -var="db_password=$DB_PASSWORD"

# Sessão caiu? Recupera outputs, DB_PASSWORD e avisa se o IP mudou:
source ../exportar-outputs.sh

# ...labs...

terraform destroy -auto-approve -var="db_password=$DB_PASSWORD"
```

## Decisões de projeto


- **Acesso só do seu IP:** `data "http"` descobre o IP de saída do CloudShell e libera só ele no RDS (5432). Se abrir um CloudShell novo e o IP mudar, rode `apply` de novo.
- **Sem segredo no código:** os scripts leem a connection string do Secrets Manager com a credencial da LabRole. `recovery_window_in_days = 0` deixa recriar o mesmo nome logo depois de um destroy.
- **Custo de lab:** RDS sem backup automático nem snapshot final, DynamoDB on-demand, bucket esvaziado e apagado no destroy (`modulos/bucket-s3`). O RDS é o item mais caro — não esqueça o destroy.
- **Learner Lab:** nada de IAM role nova; nada de região fora de `us-east-1`/`us-west-2`.
