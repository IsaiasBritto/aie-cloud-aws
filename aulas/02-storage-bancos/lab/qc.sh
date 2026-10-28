#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Atalhos do lab da Aula 2. Carregue UMA vez por sessão do CloudShell:
#
#   source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh
#
# O que o source faz:
#   - exporta os outputs do Terraform que os scripts usam (BUCKET_NAME,
#     SECRET_ID, DYNAMO_TABLE, DB_HOST, ATHENA_WORKGROUP);
#   - recupera a DB_PASSWORD do Secrets Manager (para apply/destroy);
#   - cria (se preciso) e ativa o venv /tmp/venv-qc, fora do $HOME de 1 GB;
#   - avisa se o IP do CloudShell mudou (o RDS só aceita o IP do apply);
#   - cria o comando `qc` (rode `qc` sem nada para ver a ajuda).
#
# O CloudShell encerra a sessão depois de ~20 min sem uso: rode o source de
# novo e está tudo de volta (o estado do Terraform fica no $HOME).
#
# Por que `source` e não `bash`: com `bash`, variáveis e o comando `qc`
# morrem junto com o processo.
# ---------------------------------------------------------------------------

QC_LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export QC_LAB
_qc_tf="$QC_LAB/terraform"

if [ ! -d "$_qc_tf" ]; then
  echo "ERRO: não achei a pasta terraform em $_qc_tf" >&2
  return 1 2>/dev/null || exit 1
fi

# Terraform no PATH e cache único de providers (o $HOME tem só 1 GB)
export PATH="$HOME/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Pacotes Python num venv em /tmp, fora do $HOME. O Python do CloudShell já
# roda num virtualenv e recusa "pip install --user".
if [ ! -x /tmp/venv-qc/bin/python ]; then
  python3 -m venv /tmp/venv-qc
fi
# shellcheck disable=SC1091
source /tmp/venv-qc/bin/activate

_qc_out() { terraform -chdir="$_qc_tf" output -raw "$1" 2>/dev/null; }

BUCKET_NAME="$(_qc_out bucket_name)"
SECRET_ID="$(_qc_out secret_id)"
DYNAMO_TABLE="$(_qc_out dynamodb_table)"
DB_HOST="$(_qc_out db_endpoint)"
ATHENA_WORKGROUP="$(_qc_out athena_workgroup)"
_qc_ip_tf="$(_qc_out meu_ip)"
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

# ---------------------------------------------------------------------------
# Funções internas
# ---------------------------------------------------------------------------

# Instala no venv só o que ainda não está lá (import → pacote do pip)
_qc_deps() {
  local falta=() par mod pkg
  for par in "$@"; do
    mod="${par%%=*}"; pkg="${par#*=}"
    python -c "import $mod" 2>/dev/null || falta+=("$pkg")
  done
  if [ ${#falta[@]} -gt 0 ]; then
    echo "→ Instalando no venv /tmp/venv-qc: ${falta[*]} (só na primeira vez)"
    pip install --quiet --no-cache-dir "${falta[@]}" || return 1
  fi
}

_qc_precisa() {
  local v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      echo "ERRO: $v vazio. O terraform apply terminou? Confira com: qc status" >&2
      return 1
    fi
  done
}

# Roda um SQL no Athena, espera terminar e devolve o id da consulta
_qc_athena_exec() {
  local id st
  id="$(aws athena start-query-execution --work-group "$ATHENA_WORKGROUP" \
          --query-execution-context Database=qc --query-string "$1" \
          --query QueryExecutionId --output text)" || return 1
  while :; do
    st="$(aws athena get-query-execution --query-execution-id "$id" \
            --query QueryExecution.Status.State --output text)"
    case "$st" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 1
  done
  if [ "$st" != "SUCCEEDED" ]; then
    aws athena get-query-execution --query-execution-id "$id" \
      --query QueryExecution.Status.StateChangeReason --output text >&2
    return 1
  fi
  printf '%s' "$id"
}

_qc_athena_bytes() {
  aws athena get-query-execution --query-execution-id "$1" \
    --query QueryExecution.Statistics.DataScannedInBytes --output text
}

_qc_athena_linhas() {
  aws athena get-query-results --query-execution-id "$1" \
    --query 'ResultSet.Rows[].[Data[].VarCharValue]' --output text |
    if command -v column >/dev/null; then column -t -s $'\t'; else cat; fi
}

_qc_athena() {
  local id
  id="$(_qc_athena_exec "$1")" || return 1
  _qc_athena_linhas "$id"
  echo "(lidos: $(_qc_athena_bytes "$id") bytes)"
}

# ---------------------------------------------------------------------------
# Lab 1B — o lake da QC: raw/ (CSV) → curated/ (Parquet por mês)
# ---------------------------------------------------------------------------
_QC_PERGUNTA_LAKE="SELECT categoria, ROUND(SUM(valor), 2) AS faturamento FROM %s WHERE mes = '2026-09' GROUP BY categoria ORDER BY faturamento DESC"

_qc_lake_gera() {
  _qc_precisa BUCKET_NAME ATHENA_WORKGROUP || return 1
  local csv=/tmp/qc-pedidos.csv
  python3 "$QC_LAB/scripts/gerar_pedidos.py" "$csv" || return 1
  echo "→ Subindo para s3://$BUCKET_NAME/raw/pedidos/ (camada bruta)"
  aws s3 rm "s3://$BUCKET_NAME/raw/pedidos/" --recursive --only-show-errors
  aws s3 cp "$csv" "s3://$BUCKET_NAME/raw/pedidos/pedidos.csv" --only-show-errors || return 1
  echo "→ Criando a tabela qc.pedidos_raw sobre o CSV (schema-on-read)"
  _qc_athena_exec "DROP TABLE IF EXISTS qc.pedidos_raw" >/dev/null || return 1
  _qc_athena_exec "CREATE EXTERNAL TABLE qc.pedidos_raw (
      pedido_id string, data string, cliente_id int, produto_id int, categoria string,
      uf string, canal string, quantidade int, valor double, mes string)
    ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
    LOCATION 's3://$BUCKET_NAME/raw/pedidos/'
    TBLPROPERTIES ('skip.header.line.count' = '1')" >/dev/null || return 1
  echo "✓ Camada raw pronta. Agora: qc lake cura"
  echo "  Console: S3 → $BUCKET_NAME → raw/pedidos/ (um CSV, veja o tamanho)"
}

_qc_lake_cura() {
  _qc_precisa BUCKET_NAME ATHENA_WORKGROUP || return 1
  echo "→ CTAS no Athena: o mesmo dado em Parquet, particionado por mês (~30 s)"
  _qc_athena_exec "DROP TABLE IF EXISTS qc.pedidos_curated" >/dev/null || return 1
  aws s3 rm "s3://$BUCKET_NAME/curated/pedidos/" --recursive --only-show-errors
  _qc_athena_exec "CREATE TABLE qc.pedidos_curated
    WITH (format = 'PARQUET', write_compression = 'SNAPPY',
          external_location = 's3://$BUCKET_NAME/curated/pedidos/',
          partitioned_by = ARRAY['mes'])
    AS SELECT pedido_id, data, cliente_id, produto_id, categoria, uf, canal,
              quantidade, valor, mes
       FROM qc.pedidos_raw" >/dev/null || return 1
  echo "✓ Camada curated pronta: uma pasta por mês"
  aws s3 ls "s3://$BUCKET_NAME/curated/pedidos/" | sed 's/^/  /'
  echo
  echo "  raw/     : $(aws s3 ls "s3://$BUCKET_NAME/raw/pedidos/" --recursive --summarize --human-readable | awk '/Total Size/ {print $3, $4}')"
  echo "  curated/ : $(aws s3 ls "s3://$BUCKET_NAME/curated/pedidos/" --recursive --summarize --human-readable | awk '/Total Size/ {print $3, $4}')"
  echo "Agora: qc lake compara"
}

_qc_lake_compara() {
  _qc_precisa ATHENA_WORKGROUP || return 1
  local id_raw id_cur b_raw b_cur
  echo "Pergunta: faturamento por categoria em setembro de 2026"
  echo
  id_raw="$(_qc_athena_exec "$(printf "$_QC_PERGUNTA_LAKE" qc.pedidos_raw)")" || return 1
  id_cur="$(_qc_athena_exec "$(printf "$_QC_PERGUNTA_LAKE" qc.pedidos_curated)")" || return 1
  b_raw="$(_qc_athena_bytes "$id_raw")"; b_cur="$(_qc_athena_bytes "$id_cur")"
  _qc_athena_linhas "$id_cur"
  echo
  if [ "$(_qc_athena_linhas "$id_raw")" = "$(_qc_athena_linhas "$id_cur")" ]; then
    echo "Mesmo resultado nas duas camadas."
  else
    echo "ATENÇÃO: os resultados diferem. Rode de novo: qc lake gera && qc lake cura" >&2
  fi
  python3 - "$b_raw" "$b_cur" <<'PY'
import sys
raw, cur = (int(x) for x in sys.argv[1:3])
def fmt(b):
    return f"{b/1024/1024:.2f} MB" if b >= 1024 * 1024 else f"{b/1024:.1f} KB"
print()
print(f"  raw/ (CSV)          leu {fmt(raw):>10}")
print(f"  curated/ (Parquet)  leu {fmt(cur):>10}   ({raw / max(cur, 1):.0f}x menos)")
frac = cur / raw if raw else 0
print()
print("Se o CSV tivesse 1 TB (Athena: US$ 5 por TB lido):")
print(f"  CSV     : 1 TB lido → US$ 5,00 por consulta → US$ 15.000/mês com 100 consultas/dia")
custo = 5 * frac
print(f"  Parquet : {frac*1024:.1f} GB lidos → US$ {custo:.4f} por consulta → US$ {custo*3000:,.2f}/mês".replace(",", "X").replace(".", ",").replace("X", "."))
print()
print("No lab a fatura é de centavos: o Athena cobra no mínimo 10 MB por consulta.")
PY
  echo "Console: Athena → Recent queries → coluna Data scanned das duas consultas."
  echo "Pergunta: quem decide o formato do lake na empresa de vocês? E quem paga a consulta?"
}

_qc_ajuda() {
  cat <<'AJUDA'
Uso: qc <comando>

  qc status                  o que está no ar (bucket, banco, tabela, workgroup)
  qc carga catalogo          Lab 1:  data/produtos.csv → s3://<bucket>/catalogo/
  qc carga produtos          Lab 2:  S3 → RDS, com a senha lida do Secrets Manager
  qc carga reviews           Lab 3A: 30 reviews → DynamoDB
  qc indexa                  Lab 3B: embeddings dos produtos → pgvector
  qc busca "texto"           Lab 3B: busca por palavra × busca pelo sentido
  qc sql                     abre o banco no pgcli (sair: \q; tela parada em (END): q)
  qc sql "SELECT ..."        roda uma consulta e mostra o resultado
  qc athena "SELECT ..."     roda SQL no Athena (alternativa ao console)
  qc lake gera               Lab 1B: ~200 mil pedidos → raw/pedidos/ (CSV) + tabela qc.pedidos_raw
  qc lake cura               Lab 1B: CTAS → curated/pedidos/ (Parquet, por mês)
  qc lake compara            Lab 1B: a mesma pergunta nas duas camadas, bytes lidos e custo
  qc sentimento              demo (movida para a Aula 4): sentimento das reviews

Sessão nova do CloudShell? Rode de novo:
  source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh
AJUDA
}

_qc_status() {
  echo "Bucket    : ${BUCKET_NAME:-VAZIO}"
  echo "Segredo   : ${SECRET_ID:-VAZIO}"
  echo "DynamoDB  : ${DYNAMO_TABLE:-VAZIO}"
  echo "RDS       : ${DB_HOST:-VAZIO}"
  echo "Athena    : workgroup ${ATHENA_WORKGROUP:-VAZIO}, banco qc"
  echo "Senha RDS : $([ -n "${DB_PASSWORD:-}" ] && echo 'recuperada' || echo 'VAZIA')"
  if [ -z "$BUCKET_NAME" ] || [ -z "$SECRET_ID" ]; then
    echo
    echo "AVISO: outputs vazios. O terraform apply terminou? Confira com:" >&2
    echo "       terraform -chdir=$_qc_tf output" >&2
  elif [ -n "$BUCKET_NAME" ]; then
    echo
    echo "catalogo/ no bucket:"
    aws s3 ls "s3://$BUCKET_NAME/catalogo/" | sed 's/^/  /'
  fi
}

# ---------------------------------------------------------------------------
# O comando qc
# ---------------------------------------------------------------------------
qc() {
  local scripts="$QC_LAB/scripts"
  case "${1:-}" in
    status)
      _qc_status ;;
    carga)
      case "${2:-}" in
        catalogo)
          _qc_precisa BUCKET_NAME || return 1
          aws s3 cp "$QC_LAB/data/produtos.csv" "s3://$BUCKET_NAME/catalogo/produtos.csv" --only-show-errors || return 1
          echo "✓ produtos.csv enviado para s3://$BUCKET_NAME/catalogo/"
          aws s3 ls "s3://$BUCKET_NAME/catalogo/" | sed 's/^/  /'
          echo "Console: S3 → Buckets → $BUCKET_NAME → catalogo/produtos.csv → Properties"
          ;;
        produtos)
          _qc_precisa SECRET_ID BUCKET_NAME || return 1
          _qc_deps boto3=boto3 psycopg='psycopg[binary]' || return 1
          python "$scripts/popular_produtos.py" ;;
        reviews)
          _qc_precisa DYNAMO_TABLE || return 1
          _qc_deps boto3=boto3 || return 1
          python "$scripts/popular_reviews.py" ;;
        *)
          echo "Uso: qc carga catalogo | produtos | reviews" >&2; return 1 ;;
      esac ;;
    indexa)
      _qc_precisa SECRET_ID BUCKET_NAME || return 1
      _qc_deps boto3=boto3 psycopg='psycopg[binary]' pgvector=pgvector fastembed=fastembed || return 1
      python "$scripts/indexar_produtos.py" ;;
    busca)
      shift
      [ $# -gt 0 ] || { echo 'Uso: qc busca "algo para trabalhar em pé"' >&2; return 1; }
      _qc_precisa SECRET_ID || return 1
      _qc_deps boto3=boto3 psycopg='psycopg[binary]' pgvector=pgvector fastembed=fastembed || return 1
      python "$scripts/buscar_produtos.py" "$*" ;;
    sql)
      shift
      _qc_precisa SECRET_ID || return 1
      if [ $# -eq 0 ]; then
        _qc_deps pgcli=pgcli || return 1
        local url
        url="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" \
                --query SecretString --output text)" || return 1
        # less -SRXF: resultado curto aparece direto; longo abre o paginador (sair com q)
        PAGER="less -SRXF" pgcli "$url"
      else
        _qc_deps boto3=boto3 psycopg='psycopg[binary]' || return 1
        python "$scripts/consultar.py" "$*"
      fi ;;
    lake)
      case "${2:-}" in
        gera)    _qc_lake_gera ;;
        cura)    _qc_lake_cura ;;
        compara) _qc_lake_compara ;;
        *) echo "Uso: qc lake gera | cura | compara" >&2; return 1 ;;
      esac ;;
    athena)
      shift
      [ $# -gt 0 ] || { echo 'Uso: qc athena "SELECT * FROM produtos LIMIT 5"' >&2; return 1; }
      _qc_precisa ATHENA_WORKGROUP || return 1
      _qc_athena "$*" ;;
    sentimento)
      _qc_precisa DYNAMO_TABLE || return 1
      _qc_deps boto3=boto3 || return 1
      python "$scripts/analisar_sentimento.py" ;;
    ""|ajuda|help|-h|--help)
      _qc_ajuda ;;
    *)
      echo "Comando desconhecido: $1" >&2; _qc_ajuda; return 1 ;;
  esac
}

# Atalhos antigos (guia de aprofundamento e Aula 3 ainda os citam)
qc_psql() { [ "${1:-}" = "-c" ] && shift; qc sql "$@"; }
qc_athena() { qc athena "$@"; }

# ---------------------------------------------------------------------------
# Resumo e aviso de IP
# ---------------------------------------------------------------------------
_qc_status | head -6

_qc_ip_now="$(curl -s --max-time 5 https://checkip.amazonaws.com)/32"
if [ -n "$_qc_ip_tf" ] && [ "$_qc_ip_tf" != "$_qc_ip_now" ]; then
  echo
  echo "AVISO: o IP do CloudShell mudou ($_qc_ip_tf → $_qc_ip_now)." >&2
  echo "       Libere o novo IP no RDS (~1 min):" >&2
  echo "       terraform -chdir=$_qc_tf apply -auto-approve -var=\"db_password=\$DB_PASSWORD\"" >&2
fi
echo
echo "Pronto: digite  qc  para ver os comandos do lab."

unset -f _qc_out
unset _qc_ip_tf _qc_ip_now
