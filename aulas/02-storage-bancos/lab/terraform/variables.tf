variable "region" {
  description = "Região da AWS (o Learner Lab libera us-east-1 e us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "Senha do usuário master do RDS. Gere com: openssl rand -hex 16 (o RDS não aceita / @ \" e espaço)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8 && can(regex("^[^/@\" ]+$", var.db_password))
    error_message = "A senha precisa ter 8+ caracteres e não pode conter / @ \" ou espaço."
  }
}
