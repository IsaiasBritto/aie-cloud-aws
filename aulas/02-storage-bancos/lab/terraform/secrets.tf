# Secrets Manager — a connection string NUNCA aparece no código dos scripts.
# recovery_window_in_days = 0 apaga na hora no destroy (permite recriar o mesmo nome).

resource "aws_secretsmanager_secret" "postgres" {
  name                    = "${local.nome}/postgres"
  description             = "Connection string do RDS PostgreSQL da QC (Aula 2)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id     = aws_secretsmanager_secret.postgres.id
  secret_string = "postgresql://${aws_db_instance.qc.username}:${var.db_password}@${aws_db_instance.qc.address}:${aws_db_instance.qc.port}/${aws_db_instance.qc.db_name}?sslmode=require"
}

resource "aws_secretsmanager_secret" "mongo" {
  count                   = var.criar_mongo ? 1 : 0
  name                    = "${local.nome}/mongo"
  description             = "Credenciais do MongoDB na EC2 (Lab 3C)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mongo" {
  count     = var.criar_mongo ? 1 : 0
  secret_id = aws_secretsmanager_secret.mongo[0].id
  secret_string = jsonencode({
    username = "admin"
    password = var.mongo_password
    host     = aws_instance.mongo[0].public_ip
    port     = 27017
  })
}
