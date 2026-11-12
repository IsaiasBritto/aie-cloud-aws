output "url" {
  description = "URL base da API (vai no qc chave dos alunos junto com a chave do grupo)"
  value       = aws_api_gateway_stage.v1.invoke_url
}

output "chaves" {
  description = "Chave de cada grupo. Ver com: terraform output -json chaves"
  value       = { for g, k in aws_api_gateway_api_key.grupo : g => k.value }
  sensitive   = true
}

output "chave_ids" {
  description = "Id de cada chave (aparece no log da Lambda como api_key_id)"
  value       = { for g, k in aws_api_gateway_api_key.grupo : g => k.id }
}
