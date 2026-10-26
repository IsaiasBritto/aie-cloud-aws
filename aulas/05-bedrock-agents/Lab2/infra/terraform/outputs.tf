output "bucket" {
  description = "Envie as notas para s3://<bucket>/entrada/"
  value       = module.bucket_notas.nome
}

output "fila_url" {
  description = "Use em: python gatilho/disparador.py --sqs <fila_url>"
  value       = aws_sqs_queue.fila.url
}

output "lambda" {
  description = "Logs em /aws/lambda/<lambda>"
  value       = aws_lambda_function.gatilho.function_name
}

output "proximos_passos" {
  value = <<-EOT
    python gatilho/disparador.py --s3 ${module.bucket_notas.nome}
    python gatilho/disparador.py --sqs ${aws_sqs_queue.fila.url}
    python gatilho/ciclo_do_agente.py --uma-volta
  EOT
}
