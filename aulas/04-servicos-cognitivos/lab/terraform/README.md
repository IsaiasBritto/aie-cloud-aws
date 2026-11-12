# Terraform — Aula 4

| Arquivo | O que define |
|---------|--------------|
| [main.tf](main.tf) | Providers, tags, locals, data source da LabRole |
| [variables.tf](variables.tf) | `region` (padrão `us-east-1`) |
| [outputs.tf](outputs.tf) | Os nomes que o `qc.sh` exporta |
| [storage.tf](storage.tf) | Bucket de dados + prefixos, e o evento `reviews-fotos/` → Lambda |
| [lambda.tf](lambda.tf) | Lambda Python 3.12 + Function URL + LabRole (timeout 60 s) + log group |
| [dynamodb.tf](dynamodb.tf) | Tabelas on-demand `reviews` e `produtos` |
| [secrets.tf](secrets.tf) | O segredo da API de IA, criado **vazio** |

## Como usar

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab/terraform
export PATH="$HOME/bin:$PATH" TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
terraform init && terraform apply -auto-approve
source ../qc.sh && qc publica
# ...labs...
terraform destroy -auto-approve
```

## Decisões de projeto

- **Sem recurso de IA:** Rekognition e Textract são APIs da conta, liberadas por IAM (a LabRole). Voz e sentimento vêm da API de IA da QC (pasta `professor/api-ia`), porque o Learner Lab não libera Polly, Transcribe nem Comprehend.
- **Segredo vazio no Terraform:** o `aws_secretsmanager_secret` não tem `aws_secretsmanager_secret_version`. Se tivesse, a chave do grupo ficaria no código ou no `terraform.tfstate`. O valor entra pelo `qc chave`. `recovery_window_in_days = 0` faz o destroy apagar o segredo na hora.
- **Evento do S3:** `aws_s3_bucket_notification` + `aws_lambda_permission` com `principal = "s3.amazonaws.com"` e `source_arn` do bucket: só este bucket pode invocar a função. No Learner Lab o S3 não entrega o evento (nem pelo EventBridge), e o `qc foto-review` invoca a função de forma assíncrona com o mesmo evento; numa conta normal, o upload basta.
- **Placeholder na Lambda:** o Terraform publica um handler mínimo; o código real, com dependências, vem do `qc publica`. `ignore_changes` impede o `apply` seguinte de desfazer o deploy.
- **DynamoDB:** a Lambda e o CloudShell acessam pela LabRole, sem senha, porta ou EC2. É o mesmo banco das reviews da Aula 2.
- **Function URL pública:** duas permissões na política da função (`InvokeFunctionUrl` e `InvokeFunction` com `InvokedViaFunctionUrl`), exigidas desde out/2025.
