# API Gateway REST: o tipo de API do API Gateway que tem API key e usage plan.
# Um recurso {proxy+} manda todas as rotas para a mesma Lambda.
resource "aws_api_gateway_rest_api" "api" {
  name        = local.nome
  description = "API de IA da Quantum Commerce (Polly, Transcribe, Comprehend) para os labs da Aula 4"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.proxy.id
  http_method      = "ANY"
  authorization    = "NONE"
  api_key_required = true # sem x-api-key válida, o API Gateway devolve 403 sem nem chamar a Lambda
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "ApiGatewayInvoca"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeploy = sha1(jsonencode([aws_api_gateway_resource.proxy, aws_api_gateway_method.proxy, aws_api_gateway_integration.proxy]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
  stage_name    = "v1"
}

# Cota e limite de taxa POR CHAVE: um grupo não consome a cota do outro
resource "aws_api_gateway_usage_plan" "turma" {
  name = "${local.nome}-turma"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.v1.stage_name
  }

  quota_settings {
    limit  = var.cota_diaria
    period = "DAY"
  }

  throttle_settings {
    rate_limit  = 5
    burst_limit = 10
  }
}

resource "aws_api_gateway_api_key" "grupo" {
  for_each = toset(var.grupos)
  name     = "${local.nome}-${each.key}"
}

resource "aws_api_gateway_usage_plan_key" "grupo" {
  for_each      = aws_api_gateway_api_key.grupo
  key_id        = each.value.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.turma.id
}
