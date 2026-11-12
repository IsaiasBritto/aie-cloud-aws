# Alerta de custo da conta. Com a cota por chave e o teto de concorrência, o gasto
# de uma turma fica em centavos; o budget avisa se algo fugir disso.
resource "aws_budgets_budget" "api_ia" {
  name         = "${local.nome}-mensal"
  budget_type  = "COST"
  limit_amount = tostring(var.orcamento_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [50, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.email_alerta]
    }
  }
}
