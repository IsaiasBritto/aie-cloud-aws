# Athena: SQL direto sobre o CSV que está no S3, sem banco no meio (schema-on-read).
# O Terraform prepara o ambiente; a tabela, quem escreve é o aluno, na Atividade 1.

# Banco do catálogo (Glue Data Catalog). Nome curto porque o aluno digita no SQL:
# SELECT ... FROM qc.produtos. Cada aluno tem a própria conta, então não há conflito.
resource "aws_glue_catalog_database" "qc" {
  name        = "qc"
  description = "Tabelas do Athena sobre o bucket da QC (Aula 2)"
}

# Workgroup com o local dos resultados já definido. Sem isso, o console do Athena
# para o aluno na tela "set up a query result location" antes da primeira consulta.
resource "aws_athena_workgroup" "qc" {
  name          = local.nome
  description   = "Consultas da Aula 2 (resultados em s3://<bucket>/athena/)"
  force_destroy = true # o destroy apaga o workgroup mesmo com consultas salvas

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${module.bucket_qc.nome}/athena/"
    }
  }
}
