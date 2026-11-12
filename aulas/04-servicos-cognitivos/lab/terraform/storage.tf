# Bucket de dados do lab — independente das aulas anteriores.
# audios/ (Lab 2), documentos/ (Lab 3), imagens/ e reviews-fotos/ (Lab 4)
# Criado pela AWS CLI dentro do módulo: o SCP do Learner Lab nega
# s3:GetBucketObjectLockConfiguration, que o aws_s3_bucket lê a cada refresh.
# Detalhes em modulos/bucket-s3/main.tf (o destroy também esvazia o bucket).
module "bucket_data" {
  source = "../../../../modulos/bucket-s3"
  nome   = "${local.nome}-dados"
  regiao = var.region
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = module.bucket_data.nome
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "prefixos" {
  for_each = toset(["audios/", "documentos/", "imagens/", "reviews-fotos/"])
  bucket   = module.bucket_data.nome
  key      = each.value
  content  = ""
}

# Lab 4: todo upload em reviews-fotos/ dispara a Lambda, que modera a foto.
# Ninguém chama a função: o S3 avisa. A permissão abaixo deixa o S3 (e só este
# bucket) invocar a função.
#
# No Learner Lab, o S3 NÃO entrega esse evento (nem direto, nem pelo EventBridge;
# testado em nov/2026): a configuração é aceita, mas a função nunca é acionada.
# O "qc foto-review" faz então o papel do S3 e invoca a função de forma assíncrona
# com o mesmo evento. Numa conta normal, o evento vem sozinho; a chamada do qc só
# repete o mesmo trabalho, e a moderação grava o mesmo resultado.
resource "aws_lambda_permission" "s3_invoca" {
  statement_id  = "S3ReviewsFotos"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cognitivo.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.bucket_data.arn
}

resource "aws_s3_bucket_notification" "reviews_fotos" {
  bucket = module.bucket_data.nome

  lambda_function {
    lambda_function_arn = aws_lambda_function.cognitivo.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reviews-fotos/"
  }

  depends_on = [aws_lambda_permission.s3_invoca]
}
