# Outputs consumidos pelo guia e pelo qc.sh

output "data_bucket_name" {
  description = "Bucket de dados (audios/, documentos/, imagens/, reviews-fotos/)"
  value       = module.bucket_data.nome
}

output "lambda_name" {
  description = "Nome da Lambda (qc publica)"
  value       = aws_lambda_function.cognitivo.function_name
}

output "function_url" {
  description = "URL HTTPS da Lambda (termina com /)"
  value       = aws_lambda_function_url.cognitivo.function_url
}

output "reviews_table" {
  description = "Tabela DynamoDB de reviews (partição produto, ordenação id)"
  value       = aws_dynamodb_table.reviews.name
}

output "produtos_table" {
  description = "Tabela DynamoDB do catálogo (tags do Rekognition)"
  value       = aws_dynamodb_table.produtos.name
}

output "secret_name" {
  description = "Nome do segredo da API de IA (o valor entra com qc chave)"
  value       = aws_secretsmanager_secret.api_ia.name
}
