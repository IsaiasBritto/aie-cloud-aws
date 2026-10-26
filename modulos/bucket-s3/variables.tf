variable "nome" {
  description = "Nome do bucket (global na AWS: use o sufixo aleatório do lab)"
  type        = string
}

variable "regiao" {
  description = "Região do bucket (no Learner Lab, us-east-1)"
  type        = string
}
