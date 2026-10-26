# Bucket de dados do lab (áudios e imagens) — independente das aulas anteriores
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
  for_each = toset(["audios/", "imagens/"])
  bucket   = module.bucket_data.nome
  key      = each.value
  content  = ""
}
