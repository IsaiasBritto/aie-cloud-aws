# Outputs consumidos pelo guia e pelos scripts Python (export VAR=$(terraform output -raw ...))

output "bucket_name" {
  description = "Bucket S3 da QC (prefixos catalogo/, imagens/, logs/)"
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

output "meu_ip" {
  description = "IP do CloudShell liberado no RDS"
  value       = local.meu_ip_cidr
}
