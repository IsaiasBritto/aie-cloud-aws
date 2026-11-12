# Lab 2: o "cofre" da chave da API de IA da QC (serviço de terceiro).
#
# O Terraform cria só o segredo, VAZIO. O valor (URL + chave do grupo) entra pelo
# comando  qc chave, direto no Secrets Manager. Assim a chave nunca passa pelo
# código, pelo terraform.tfstate nem pelo repositório.
#
# recovery_window_in_days = 0: o destroy apaga na hora. O padrão (7 a 30 dias
# agendado) seguiria cobrando US$ 0,40/mês proporcional e travaria o nome.
resource "aws_secretsmanager_secret" "api_ia" {
  name                    = "${local.nome}/api-ia"
  description             = "URL e API key do grupo para a API de IA da QC (preenchido com qc chave)"
  recovery_window_in_days = 0
}
