# Use module.<nome>.nome onde antes estava aws_s3_bucket.<nome>.id ou .bucket.
# Vem do terraform_data, então quem usa o nome só roda depois do bucket existir.
output "nome" {
  description = "Nome do bucket"
  value       = terraform_data.bucket.output.nome
}

output "arn" {
  description = "ARN do bucket"
  value       = "arn:aws:s3:::${terraform_data.bucket.output.nome}"
}
