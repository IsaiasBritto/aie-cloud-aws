variable "region" {
  description = "Região da API (a mesma do Learner Lab ajuda na latência)"
  type        = string
  default     = "us-east-1"
}

variable "grupos" {
  description = "Uma API key por nome. Tirar um nome da lista e dar apply revoga só aquela chave."
  type        = list(string)
  default     = ["grupo-01", "grupo-02", "grupo-03", "grupo-04", "grupo-05", "grupo-06", "grupo-07", "grupo-08", "professor"]
}

variable "cota_diaria" {
  description = "Chamadas por dia por chave (o lab inteiro usa umas 30)"
  type        = number
  default     = 300
}

variable "orcamento_usd" {
  description = "Teto mensal do AWS Budget; o alerta sai em 50% e 100%"
  type        = number
  default     = 10
}

variable "email_alerta" {
  description = "E-mail que recebe o alerta do orçamento (fica só no seu terraform.tfvars, fora do Git)"
  type        = string
}
