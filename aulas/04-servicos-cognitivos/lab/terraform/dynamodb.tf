# Reviews da QC no DynamoDB — o mesmo banco da Aula 2, gerenciado e sem senha.
# A Lambda e o CloudShell acessam pela LabRole: nenhuma credencial, nenhuma porta aberta.
# Chave de partição "produto": todas as reviews de um produto na mesma "gaveta",
# o que permite uma Query barata por produto (exercício 3.3).
resource "aws_dynamodb_table" "reviews" {
  name         = "${local.nome}-reviews"
  billing_mode = "PAY_PER_REQUEST" # on-demand: paga por requisição, nada parado
  hash_key     = "produto"
  range_key    = "id"

  attribute {
    name = "produto"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }
}
