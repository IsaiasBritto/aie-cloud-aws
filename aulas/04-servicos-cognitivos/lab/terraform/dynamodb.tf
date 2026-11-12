# Reviews e catálogo da QC no DynamoDB — o mesmo banco da Aula 2, gerenciado e sem senha.
# A Lambda e o CloudShell acessam pela LabRole: nenhuma credencial, nenhuma porta aberta.

# Reviews (Labs 1, 3 e 4). Partição "produto": todas as reviews de um produto na
# mesma "gaveta", o que permite uma Query barata por produto.
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

# Catálogo (Lab 4): as tags que o Rekognition tirou da foto de cada produto
resource "aws_dynamodb_table" "produtos" {
  name         = "${local.nome}-produtos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "produto"

  attribute {
    name = "produto"
    type = "S"
  }
}
