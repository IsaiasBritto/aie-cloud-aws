# Bucket temporário: o Transcribe só lê áudio do S3. O handler apaga cada áudio
# ao terminar; o lifecycle é a rede de segurança.
resource "aws_s3_bucket" "temp" {
  bucket        = "${local.nome}-temp"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "temp" {
  bucket                  = aws_s3_bucket.temp.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "temp" {
  bucket = aws_s3_bucket.temp.id

  rule {
    id     = "apaga-em-1-dia"
    status = "Enabled"
    filter {}
    expiration {
      days = 1
    }
  }
}

# Na sua conta dá para criar role: aqui ela tem só o que a função usa (menor privilégio)
resource "aws_iam_role" "api" {
  name = "${local.nome}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "api" {
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["polly:SynthesizeSpeech"], Resource = "*" },
      { Effect = "Allow", Action = ["comprehend:BatchDetectSentiment", "comprehend:BatchDetectEntities"], Resource = "*" },
      { Effect = "Allow", Action = ["rekognition:DetectLabels", "rekognition:DetectText"], Resource = "*" }, # só o app da demo
      {
        Effect   = "Allow"
        Action   = ["transcribe:StartTranscriptionJob", "transcribe:GetTranscriptionJob", "transcribe:DeleteTranscriptionJob"]
        Resource = "*"
      },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.temp.arn}/*" },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.api.arn}:*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.nome}"
  retention_in_days = 14
}

data "archive_file" "api" {
  type        = "zip"
  source_file = "${path.module}/../function/handler.py"
  output_path = "${path.module}/.build/api.zip"
}

resource "aws_lambda_function" "api" {
  function_name    = local.nome
  role             = aws_iam_role.api.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 28 # o API Gateway corta em 29 s
  memory_size      = 256

  # Teto de execuções simultâneas: mesmo com uma chave vazada, o estrago tem limite
  reserved_concurrent_executions = 20

  environment {
    variables = { BUCKET_TEMP = aws_s3_bucket.temp.id }
  }

  depends_on = [aws_cloudwatch_log_group.api, aws_iam_role_policy.api]
}
