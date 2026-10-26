# Outputs consumidos pelo guia, pelos scripts e pelo app (exportar-outputs.sh)

output "data_bucket_name" {
  description = "Bucket de dados (prefixos audios/ e imagens/)"
  value       = module.bucket_data.nome
}

output "lambda_name" {
  description = "Nome da Lambda (aws lambda update-function-code)"
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
