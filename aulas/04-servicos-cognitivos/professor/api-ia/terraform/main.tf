# API de IA da QC — Terraform da conta do PROFESSOR (não do Learner Lab).
#
# Sobe uma Lambda com Polly, Transcribe e Comprehend atrás de um API Gateway REST
# com uma API key por grupo. Os alunos consomem pela Lambda deles, com a chave
# guardada no Secrets Manager do Learner Lab.
#
# Nenhuma chave vai para o repositório: elas nascem aqui e ficam no SEU
# terraform.tfstate local (que o .gitignore já exclui). Distribua fora do Git.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      disciplina   = "cloud-cognitive"
      projeto      = "quantum-commerce"
      componente   = "api-ia-professor"
      provisionado = "terraform"
    }
  }
}

resource "random_string" "sufixo" {
  length  = 6
  upper   = false
  special = false
}

locals {
  nome = "qc-api-ia-${random_string.sufixo.result}"
}

data "aws_caller_identity" "eu" {}
