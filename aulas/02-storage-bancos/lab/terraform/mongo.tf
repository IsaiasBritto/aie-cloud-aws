# MongoDB 7.0 + Mongo Express numa EC2 com Docker (Lab 3C — demo do professor, opcional).
# Só é criado com criar_mongo = true (ex.: export TF_VAR_criar_mongo=true antes do apply).
# As imagens vêm do espelho oficial no ECR Public (public.ecr.aws/docker/library),
# sem o limite de pulls anônimos do Docker Hub.

data "aws_ami" "al2023" {
  count       = var.criar_mongo ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "mongo" {
  count       = var.criar_mongo ? 1 : 0
  name        = "${local.nome}-mongo"
  description = "MongoDB so para o CloudShell; Mongo Express com senha"
  vpc_id      = data.aws_vpc.padrao.id

  ingress {
    description = "MongoDB"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [local.meu_ip_cidr]
  }

  ingress {
    description = "Mongo Express (navegador do aluno), protegido por usuario e senha"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.mongo_ui_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "mongo" {
  count                       = var.criar_mongo ? 1 : 0
  ami                         = data.aws_ami.al2023[0].id
  instance_type               = var.mongo_instance_type
  vpc_security_group_ids      = [aws_security_group.mongo[0].id]
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/mongo-user-data.sh.tftpl", {
    mongo_password    = var.mongo_password
    mongo_ui_password = var.mongo_ui_password
  })

  tags = {
    Name = "${local.nome}-mongo"
  }
}
