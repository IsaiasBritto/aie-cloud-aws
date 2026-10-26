#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Recupera a sessão da Aula 2 no CloudShell:
#   - exporta os outputs do Terraform que os scripts Python usam;
#   - recupera a DB_PASSWORD do Secrets Manager (para apply/destroy);
#   - cria (se preciso) e ativa o venv /tmp/venv-qc, fora do $HOME de 1 GB;
#   - avisa se o IP do CloudShell mudou (RDS e Mongo só aceitam o IP antigo).
#
#   source ~/aie-cloud/aulas/02-storage-bancos/lab/exportar-outputs.sh
#
# Precisa ser carregado com "source": com "bash", as variáveis morrem junto
# com o processo. Rode sempre que abrir um terminal novo — o CloudShell
# encerra a sessão depois de ~20 min sem uso.
# ---------------------------------------------------------------------------

_qc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/terraform"

if [ ! -d "$_qc_dir" ]; then
  echo "ERRO: não achei a pasta terraform em $_qc_dir" >&2
  return 1 2>/dev/null || exit 1
fi

# Terraform no PATH e cache único de providers (o $HOME tem só 1 GB)
export PATH="$HOME/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Pacotes Python num venv em /tmp, fora do $HOME (que tem só 1 GB). O Python do
# CloudShell já roda num virtualenv e recusa "pip install --user".
if [ ! -x /tmp/venv-qc/bin/python ]; then
  python3 -m venv /tmp/venv-qc
fi
# shellcheck disable=SC1091
source /tmp/venv-qc/bin/activate

_qc_out() { terraform -chdir="$_qc_dir" output -raw "$1" 2>/dev/null; }

BUCKET_NAME="$(_qc_out bucket_name)"
SECRET_ID="$(_qc_out secret_id)"
DYNAMO_TABLE="$(_qc_out dynamodb_table)"
DB_HOST="$(_qc_out db_endpoint)"
MONGO_IP="$(_qc_out mongodb_public_ip)"
MONGO_SECRET_ID="$(_qc_out mongo_secret_id)"
export BUCKET_NAME SECRET_ID DYNAMO_TABLE DB_HOST MONGO_IP MONGO_SECRET_ID

# Senha do RDS: se a sessão caiu, ela está na connection string do segredo
if [ -z "${DB_PASSWORD:-}" ] && [ -n "$SECRET_ID" ]; then
  _qc_conn="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" \
              --query SecretString --output text 2>/dev/null)"
  DB_PASSWORD="$(printf '%s' "$_qc_conn" | sed -E 's#^postgresql://[^:]+:([^@]+)@.*#\1#')"
  [ "$DB_PASSWORD" = "$_qc_conn" ] && DB_PASSWORD=""
  export DB_PASSWORD
  unset _qc_conn
fi

echo "Bucket    : ${BUCKET_NAME:-VAZIO}"
echo "Secret    : ${SECRET_ID:-VAZIO}"
echo "DynamoDB  : ${DYNAMO_TABLE:-VAZIO}"
echo "RDS       : ${DB_HOST:-VAZIO}"
echo "Senha RDS : $([ -n "${DB_PASSWORD:-}" ] && echo 'recuperada' || echo 'VAZIA')"
if [ -n "$MONGO_IP" ]; then
  echo "MongoDB   : $MONGO_IP:27017  |  Mongo Express: http://$MONGO_IP:8081"
else
  echo "MongoDB   : não criado (demo do professor: TF_VAR_criar_mongo=true)"
fi

if [ -z "$BUCKET_NAME" ] || [ -z "$SECRET_ID" ]; then
  echo
  echo "AVISO: outputs vazios. O terraform apply completou? Rode 'terraform output'" >&2
  echo "       em $_qc_dir para conferir." >&2
fi

# IP do CloudShell mudou? Então RDS e Mongo vão dar timeout até reaplicar.
_qc_ip_tf="$(_qc_out meu_ip)"
_qc_ip_now="$(curl -s --max-time 5 https://checkip.amazonaws.com)/32"
if [ -n "$_qc_ip_tf" ] && [ "$_qc_ip_tf" != "$_qc_ip_now" ]; then
  echo
  echo "AVISO: o IP do CloudShell mudou ($_qc_ip_tf → $_qc_ip_now)." >&2
  echo "       Libere o novo IP no RDS/Mongo (~1 min):" >&2
  echo "       terraform -chdir=$_qc_dir apply -auto-approve -var=\"db_password=\$DB_PASSWORD\"" >&2
fi

unset -f _qc_out
unset _qc_dir _qc_ip_tf _qc_ip_now
