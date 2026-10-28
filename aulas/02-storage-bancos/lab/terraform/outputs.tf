# Outputs consumidos pelo guia e pelos scripts Python (export VAR=$(terraform output -raw ...))

output "bucket_name" {
  description = "Bucket S3 da QC (prefixos catalogo/, imagens/, logs/ e as camadas raw/ e curated/ do lake)"
  value       = module.bucket_qc.nome
}

output "secret_id" {
  description = "Segredo com a connection string do PostgreSQL"
  value       = aws_secretsmanager_secret.postgres.name
}

output "dynamodb_table" {
  description = "Tabela DynamoDB de reviews (chave produto_id + review_id)"
  value       = aws_dynamodb_table.reviews.name
}

output "db_endpoint" {
  description = "Host do RDS PostgreSQL"
  value       = aws_db_instance.qc.address
}

output "db_name" {
  description = "Banco de dados do RDS"
  value       = aws_db_instance.qc.db_name
}

output "athena_workgroup" {
  description = "Workgroup do Athena (escolha este no console antes de consultar)"
  value       = aws_athena_workgroup.qc.name
}

output "glue_database" {
  description = "Banco do catálogo onde o aluno cria a tabela do Athena"
  value       = aws_glue_catalog_database.qc.name
}

output "meu_ip" {
  description = "IP do CloudShell liberado no RDS"
  value       = local.meu_ip_cidr
}
