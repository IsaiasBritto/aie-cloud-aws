#!/usr/bin/env bash
# Apaga tudo o que o Lab2 criou na conta (bucket, fila, Lambda, regra, logs).
# Rode ao final da aula: o Learner Lab tem orçamento limitado.
set -euo pipefail
cd "$(dirname "$0")/terraform"

if [ ! -f terraform.tfstate ]; then
  echo "Nada para remover: não há terraform.tfstate nesta pasta."
  exit 0
fi

terraform destroy -auto-approve
rm -f gatilho.zip
echo "✓ Lab2 removido. Confira em S3, SQS e Lambda que não sobrou nada com 'deva-lab2-'."
