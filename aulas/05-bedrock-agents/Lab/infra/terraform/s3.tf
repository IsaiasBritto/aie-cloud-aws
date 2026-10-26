# O bucket guarda o resultado de cada análise (e a imagem, só com
# consentimento). Três decisões de LGPD estão aqui, em código:

# Criado pela AWS CLI dentro do módulo: o SCP do Learner Lab nega
# s3:GetBucketObjectLockConfiguration, que o aws_s3_bucket lê a cada refresh.
# Detalhes em modulos/bucket-s3/main.tf (o destroy também esvazia o bucket).
module "bucket_deteccoes" {
  source = "../../../../../modulos/bucket-s3"
  nome   = "${local.nome}-deteccoes"
  regiao = var.region
}

# 1. Ninguém de fora lê. Nunca.
resource "aws_s3_bucket_public_access_block" "deteccoes" {
  bucket                  = module.bucket_deteccoes.nome
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. Criptografado em repouso.
resource "aws_s3_bucket_server_side_encryption_configuration" "deteccoes" {
  bucket = module.bucket_deteccoes.nome
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 3. Prazo de retenção que se cumpre sozinho. "Vamos apagar depois" não é
#    política; regra de ciclo de vida é.
resource "aws_s3_bucket_lifecycle_configuration" "deteccoes" {
  bucket = module.bucket_deteccoes.nome
  rule {
    id     = "lgpd-retencao"
    status = "Enabled"
    filter {
      prefix = "deteccoes/"
    }
    expiration {
      days = var.retencao_dias
    }
  }
}
