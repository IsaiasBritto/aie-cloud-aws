# Lab2 — o gatilho contínuo do Deva na AWS (Learner Lab).
#
#   S3 (entrada/)  ──Object Created──▶  EventBridge (regra: prefixo entrada/)
#                                            │
#                                            ▼
#                                     Lambda deva-gatilho  ──▶  SQS deva-fila
#                                                                   │
#   disparador.py --sqs  (CloudShell ou sua máquina) ◀──────────────┘
#        └─▶ POST /fila na API ─▶ ciclo_do_agente.py --uma-volta
#
# Sem IAM novo: o Learner Lab não deixa criar role, então a Lambda roda com a LabRole.
# Custo de uma turma inteira: centavos (Lambda, SQS e EventBridge têm camada gratuita).

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      aula         = "5"
      disciplina   = "cloud-cognitive"
      projeto      = "deva-lab2"
      provisionado = "terraform"
    }
  }
}

resource "random_string" "sufixo" {
  length  = 6
  upper   = false
  special = false
}

locals {
  nome = "deva-lab2-${random_string.sufixo.result}"
}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

# ---------- bucket: entrada/ dispara; memoria/ e saida/ não ----------
# Criado pela AWS CLI dentro do módulo: o SCP do Learner Lab nega
# s3:GetBucketObjectLockConfiguration, que o aws_s3_bucket lê a cada refresh.
# Detalhes em modulos/bucket-s3/main.tf (o destroy também esvazia o bucket).
module "bucket_notas" {
  source = "../../../../../modulos/bucket-s3"
  nome   = local.nome
  regiao = var.region
}

resource "aws_s3_bucket_public_access_block" "notas" {
  bucket                  = module.bucket_notas.nome
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Liga o envio de TODOS os eventos do bucket para o EventBridge; quem filtra é a regra.
resource "aws_s3_bucket_notification" "notas" {
  bucket      = module.bucket_notas.nome
  eventbridge = true
}

# ---------- fila que desacopla o gatilho do agente ----------
resource "aws_sqs_queue" "fila" {
  name                       = "${local.nome}-fila"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 86400
}

# ---------- Lambda do gatilho ----------
data "archive_file" "gatilho" {
  type        = "zip"
  source_file = "${path.module}/../../gatilho/lambda_gatilho.py"
  output_path = "${path.module}/gatilho.zip"
}

resource "aws_lambda_function" "gatilho" {
  function_name    = "${local.nome}-gatilho"
  role             = data.aws_iam_role.lab.arn
  runtime          = "python3.12"
  handler          = "lambda_gatilho.lambda_handler"
  filename         = data.archive_file.gatilho.output_path
  source_code_hash = data.archive_file.gatilho.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      FILA_URL = aws_sqs_queue.fila.url
    }
  }
}

resource "aws_cloudwatch_log_group" "gatilho" {
  name              = "/aws/lambda/${aws_lambda_function.gatilho.function_name}"
  retention_in_days = 3
}

# ---------- regra: o filtro de verdade, antes de acordar a Lambda ----------
resource "aws_cloudwatch_event_rule" "entrada" {
  name        = "${local.nome}-entrada"
  description = "Só objetos novos em entrada/ disparam o ciclo do Deva"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [module.bucket_notas.nome] }
      object = { key = [{ prefix = "entrada/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "gatilho" {
  rule = aws_cloudwatch_event_rule.entrada.name
  arn  = aws_lambda_function.gatilho.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "PermitirEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gatilho.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.entrada.arn
}
