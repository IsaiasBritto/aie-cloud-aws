# Bucket S3 criado pela AWS CLI, e não pelo recurso aws_s3_bucket.
#
# Por quê: o service control policy (SCP) do AWS Academy Learner Lab nega
# s3:GetBucketObjectLockConfiguration. O recurso aws_s3_bucket do provider
# chama essa API toda vez que lê o bucket (no apply, no plan e no destroy), e
# o erro AccessDenied derruba o Terraform logo depois de criar o bucket:
#
#   Error: reading S3 Bucket (...) object lock configuration: ... AccessDenied
#   ... with an explicit deny in a service control policy
#
# Aqui o bucket nasce e morre por comandos da CLI (CreateBucket, PutBucketTagging,
# DeleteBucket), que o Learner Lab permite. Os demais recursos de S3 do lab
# (bloqueio público, criptografia, lifecycle, versionamento, objetos) continuam
# sendo aws_s3_* normais e apontam para module.<nome>.nome.
#
# Fora do Learner Lab, numa conta sua, use o aws_s3_bucket normal.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Mesmas tags do default_tags do provider do lab (aula, disciplina, projeto...)
data "aws_default_tags" "atual" {}

locals {
  tagging = jsonencode({
    TagSet = [for chave, valor in data.aws_default_tags.atual.tags : { Key = chave, Value = valor }]
  })
}

resource "terraform_data" "bucket" {
  input = {
    nome   = var.nome
    regiao = var.regiao
  }

  # Cria (ou reaproveita, se já existir na sua conta) e aplica as tags.
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      BUCKET  = self.input.nome
      REGIAO  = self.input.regiao
      TAGGING = local.tagging
    }
    command = <<-EOT
      set -euo pipefail
      if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
        echo "Bucket $BUCKET já existe na conta: reaproveitando."
      elif [ "$REGIAO" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGIAO" >/dev/null
      else
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGIAO" \
          --create-bucket-configuration "LocationConstraint=$REGIAO" >/dev/null
      fi
      aws s3api wait bucket-exists --bucket "$BUCKET"
      if [ "$TAGGING" != '{"TagSet":[]}' ]; then
        aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "$TAGGING"
      fi
      echo "Bucket $BUCKET pronto."
    EOT
  }

  # No destroy: esvazia (inclusive versões, para buckets com versionamento) e apaga.
  # Equivale ao force_destroy = true do aws_s3_bucket.
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    environment = {
      BUCKET = self.input.nome
    }
    command = <<-EOT
      set -uo pipefail
      if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
        echo "Bucket $BUCKET não existe mais: nada a apagar."
        exit 0
      fi
      for tipo in Versions DeleteMarkers; do
        while true; do
          lote=$(aws s3api list-object-versions --bucket "$BUCKET" --max-items 1000 --output json \
            --query '{Objects: '"$tipo"'[].{Key: Key, VersionId: VersionId}, Quiet: `true`}')
          echo "$lote" | grep -q '"Key"' || break
          aws s3api delete-objects --bucket "$BUCKET" --delete "$lote" >/dev/null || break
        done
      done
      aws s3 rm "s3://$BUCKET" --recursive --quiet || true
      aws s3api delete-bucket --bucket "$BUCKET"
      echo "Bucket $BUCKET apagado."
    EOT
  }
}
