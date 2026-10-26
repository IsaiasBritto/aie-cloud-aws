# Bucket do CATÁLOGO da QC — criado NESTA aula (a Aula 3 não depende da Aula 2)
# Criado pela AWS CLI dentro do módulo: o SCP do Learner Lab nega
# s3:GetBucketObjectLockConfiguration, que o aws_s3_bucket lê a cada refresh.
# Detalhes em modulos/bucket-s3/main.tf (o destroy também esvazia o bucket).
module "bucket_catalogo" {
  source = "../../../../modulos/bucket-s3"
  nome   = "${local.nome}-catalogo"
  regiao = var.region
}

resource "aws_s3_bucket_public_access_block" "catalogo" {
  bucket                  = module.bucket_catalogo.nome
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sobe o produtos.csv no apply — sem passo de upload manual
resource "aws_s3_object" "produtos" {
  bucket       = module.bucket_catalogo.nome
  key          = "catalogo/produtos.csv"
  source       = "${path.module}/../data/produtos.csv"
  etag         = filemd5("${path.module}/../data/produtos.csv")
  content_type = "text/csv"
}
