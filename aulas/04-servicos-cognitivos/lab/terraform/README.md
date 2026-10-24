# Terraform — Aula 4

| Arquivo | O que define |
|---------|--------------|
| [main.tf](main.tf) | Providers, tags, locals, data source da LabRole |
| [variables.tf](variables.tf) | `region` (padrão `us-east-1`) |
| [outputs.tf](outputs.tf) | `data_bucket_name`, `lambda_name`, `function_url`, `reviews_table` |
| [storage.tf](storage.tf) | Bucket de dados + prefixos `audios/` e `imagens/` |
| [lambda.tf](lambda.tf) | Lambda Python 3.12 + Function URL + LabRole (timeout 60 s) + log group |
| (nenhum) | Nada a criar: Transcribe, Polly, Comprehend e Rekognition são APIs da conta |
| [dynamodb.tf](dynamodb.tf) | Tabela on-demand `reviews` (partição `produto`, ordenação `id`) |

## Como usar

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab/terraform
export PATH="$HOME/bin:$PATH" TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
terraform init && terraform apply -auto-approve
cd .. && source exportar-outputs.sh
# ...labs...
cd terraform && terraform destroy -auto-approve
```

## Decisões de projeto

- **Sem recurso de IA:** na AWS os serviços de IA são APIs da conta. O acesso é IAM puro — a LabRole da Lambda.
- **Placeholder na Lambda:** o Terraform publica um handler mínimo; o código real, com dependências, é publicado no Lab 2. `ignore_changes` impede o `apply` seguinte de desfazer o deploy.
- **DynamoDB em vez de banco autogerenciado:** a versão anterior usava MongoDB numa EC2, o que exigia senha no cliente e a porta 27017 aberta para a internet (a Lambda roda fora da VPC). Com o DynamoDB, a Lambda e o CloudShell acessam pela LabRole: sem senha, sem porta, sem EC2. É o mesmo banco das reviews da Aula 2.
- **Function URL pública:** duas permissões na política da função (`InvokeFunctionUrl` e `InvokeFunction` com `InvokedViaFunctionUrl`), exigidas desde out/2025.
