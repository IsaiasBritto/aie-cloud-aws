#!/usr/bin/env bash
# Pré-voo da Aula 4: a sessão do Learner Lab chega a tudo o que o lab usa?
# Rode ANTES do terraform apply — descobrir no meio do Lab 4 custa a aula.
# Uso: bash check_servicos.sh
#
# Voz e sentimento (Polly, Transcribe, Comprehend) não aparecem aqui: o Learner
# Lab não libera esses serviços, e o lab usa a API de IA da QC, do professor.
REGIAO="${AWS_REGION:-$(aws configure get region)}"
REGIAO="${REGIAO:-us-east-1}"
IMG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data/produto.jpg"
echo "Região: $REGIAO"

ok()   { echo "  ✓ $1"; }
falha(){ echo "  ✗ $1"; FALHOU=1; }
FALHOU=0
chk()  { local nome="$1"; shift; "$@" --region "$REGIAO" >/dev/null 2>&1 && ok "$nome" || falha "$nome"; }

chk "Credenciais (Learner Lab ativo)"    aws sts get-caller-identity
chk "S3"                                 aws s3api list-buckets
chk "Lambda"                             aws lambda list-functions --max-items 1
chk "DynamoDB"                           aws dynamodb list-tables --max-items 1
chk "Secrets Manager"                    aws secretsmanager list-secrets --max-results 1
chk "Rekognition (rótulos)"              aws rekognition detect-labels --image-bytes "fileb://$IMG" --max-labels 1
chk "Rekognition (moderação)"            aws rekognition detect-moderation-labels --image-bytes "fileb://$IMG"
chk "Textract (formulários)"             aws textract analyze-document --feature-types FORMS --document "{\"Bytes\":\"$(base64 -w0 "$IMG")\"}"

[ "$FALHOU" = 0 ] && echo "Tudo pronto para o terraform apply." \
  || { echo "Corrija os itens com ✗ (Start Lab / CloudShell novo) antes de seguir."; exit 1; }
