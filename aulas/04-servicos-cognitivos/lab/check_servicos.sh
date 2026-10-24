#!/usr/bin/env bash
# Pré-voo da Aula 4: a sessão do Learner Lab chega aos serviços de IA e ao resto
# do lab? Rode ANTES do terraform apply — descobrir no meio do Lab 2 custa a aula.
# Uso: bash check_servicos.sh
REGIAO="${AWS_REGION:-$(aws configure get region)}"
REGIAO="${REGIAO:-us-east-1}"
echo "Região: $REGIAO"

ok()   { echo "  ✓ $1"; }
falha(){ echo "  ✗ $1"; FALHOU=1; }
FALHOU=0
chk()  { local nome="$1"; shift; "$@" --region "$REGIAO" >/dev/null 2>&1 && ok "$nome" || falha "$nome"; }

chk "Credenciais (Learner Lab ativo)" aws sts get-caller-identity
chk "S3"                               aws s3api list-buckets
chk "Lambda"                           aws lambda list-functions --max-items 1
chk "DynamoDB"                         aws dynamodb list-tables --max-items 1
chk "Polly (vozes pt-BR)"              aws polly describe-voices --language-code pt-BR
chk "Transcribe"                       aws transcribe list-transcription-jobs --max-results 1
chk "Comprehend (sentimento em pt)"    aws comprehend detect-sentiment --language-code pt --text "Gostei muito"
chk "Rekognition"                      aws rekognition list-collections --max-results 1

[ "$FALHOU" = 0 ] && echo "Tudo pronto para o terraform apply." \
  || { echo "Corrija os itens com ✗ (Start Lab / CloudShell novo) antes de seguir."; exit 1; }
