#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Recupera a sessão da Aula 2 no CloudShell:
#   - exporta os outputs do Terraform que os scripts Python usam;
#   - recupera a DB_PASSWORD do Secrets Manager (para apply/destroy);
#   - cria (se preciso) e ativa o venv /tmp/venv-qc, fora do $HOME de 1 GB;
#   - cria os atalhos qc_psql (abre o banco sem mostrar a senha) e qc_athena;
#   - avisa se o IP do CloudShell mudou (o RDS só aceita o IP antigo).
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
ATHENA_WORKGROUP="$(_qc_out athena_workgroup)"
export BUCKET_NAME SECRET_ID DYNAMO_TABLE DB_HOST ATHENA_WORKGROUP

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
echo "Athena    : workgroup ${ATHENA_WORKGROUP:-VAZIO}, banco qc"
echo "Senha RDS : $([ -n "${DB_PASSWORD:-}" ] && echo 'recuperada' || echo 'VAZIA')"

if [ -z "$BUCKET_NAME" ] || [ -z "$SECRET_ID" ]; then
  echo
  echo "AVISO: outputs vazios. O terraform apply completou? Rode 'terraform output'" >&2
  echo "       em $_qc_dir para conferir." >&2
fi

# Atalho para abrir o PostgreSQL do RDS. A connection string (com a senha) vem do
# Secrets Manager na hora e não aparece na tela nem fica numa variável.
#   qc_psql                       -> modo interativo (pgcli, se instalado; senão psql)
#   qc_psql -c "SELECT ..."       -> uma consulta só (psql)
qc_psql() {
  local _url
  _url="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" \
          --query SecretString --output text)" || return 1
  if [ $# -eq 0 ] && command -v pgcli >/dev/null 2>&1; then
    # less -SRXF: resultado curto aparece direto; longo abre o paginador (sair com q)
    PAGER="less -SRXF" pgcli "$_url"
  elif command -v psql >/dev/null 2>&1; then
    psql "$_url" "$@"
  else
    echo "Instale um cliente: pip install pgcli  (ou: sudo dnf install -y postgresql16 < /dev/null)" >&2
    return 1
  fi
}

# Atalho para o Athena no terminal (alternativa ao console). Usa o workgroup do
# lab e o banco qc; mostra o resultado em colunas e quantos bytes foram lidos.
#   qc_athena "SELECT * FROM produtos LIMIT 5"
qc_athena() {
  local _id _st
  _id="$(aws athena start-query-execution --work-group "$ATHENA_WORKGROUP" \
          --query-execution-context Database=qc --query-string "$1" \
          --query QueryExecutionId --output text)" || return 1
  while :; do
    _st="$(aws athena get-query-execution --query-execution-id "$_id" \
            --query QueryExecution.Status.State --output text)"
    case "$_st" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 1
  done
  if [ "$_st" != "SUCCEEDED" ]; then
    aws athena get-query-execution --query-execution-id "$_id" \
      --query QueryExecution.Status.StateChangeReason --output text >&2
    return 1
  fi
  aws athena get-query-results --query-execution-id "$_id" \
    --query 'ResultSet.Rows[].[Data[].VarCharValue]' --output text | column -t -s $'\t'
  echo "(lidos: $(aws athena get-query-execution --query-execution-id "$_id" \
    --query QueryExecution.Statistics.DataScannedInBytes --output text) bytes)"
}

# IP do CloudShell mudou? Então o RDS vai dar timeout até reaplicar.
_qc_ip_tf="$(_qc_out meu_ip)"
_qc_ip_now="$(curl -s --max-time 5 https://checkip.amazonaws.com)/32"
if [ -n "$_qc_ip_tf" ] && [ "$_qc_ip_tf" != "$_qc_ip_now" ]; then
  echo
  echo "AVISO: o IP do CloudShell mudou ($_qc_ip_tf → $_qc_ip_now)." >&2
  echo "       Libere o novo IP no RDS (~1 min):" >&2
  echo "       terraform -chdir=$_qc_dir apply -auto-approve -var=\"db_password=\$DB_PASSWORD\"" >&2
fi

unset -f _qc_out
unset _qc_dir _qc_ip_tf _qc_ip_now
