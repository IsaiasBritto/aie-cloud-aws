#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Atalhos do lab da Aula 3. Carregue UMA vez por sessão do CloudShell,
# depois do terraform apply:
#
#   source ~/aie-cloud/aulas/03-serverless-containers/lab/qc.sh
#
# O que o source faz:
#   - exporta os outputs do Terraform que os comandos usam (BUCKET_NAME,
#     FUNCTION_NAME, FUNCTION_URL, ECR_URL, ECS_CLUSTER);
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

_qc_carrega() {
  _qc_out() { terraform -chdir="$_qc_tf" output -raw "$1" 2>/dev/null; }
  BUCKET_NAME="$(_qc_out bucket_name)"
  FUNCTION_NAME="$(_qc_out lambda_name)"
  FUNCTION_URL="$(_qc_out function_url)"
  ECR_URL="$(_qc_out ecr_repository_url)"
  ECS_CLUSTER="$(_qc_out ecs_cluster_name)"
  export BUCKET_NAME FUNCTION_NAME FUNCTION_URL ECR_URL ECS_CLUSTER
  unset -f _qc_out
}
_qc_carrega

# ---------------------------------------------------------------------------
# Funções internas
# ---------------------------------------------------------------------------

_qc_precisa() {
  local v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      echo "ERRO: $v vazio. O terraform apply terminou? Confira com: qc status" >&2
      return 1
    fi
  done
}

# Caminho da chamada: sempre começa com "/" (aceita "produtos" ou "/produtos")
_qc_caminho() {
  local c="${1:-/produtos}"
  [ "${c#/}" = "$c" ] && c="/$c"
  printf '%s' "$c"
}

# Faz a requisição e devolve "status tempo" na última linha; o corpo vai para $2
_qc_get() {
  curl -s -m 30 -o "$2" -w '%{http_code} %{time_total}' "$1"
}

# JSON legível, com acentos (sem é)
_qc_json() {
  python3 -c 'import json,sys
try:
    print(json.dumps(json.load(sys.stdin), ensure_ascii=False, indent=2))
except Exception:
    sys.stdout.write(open(sys.argv[1]).read() if len(sys.argv) > 1 else "")' "$1" < "$1"
}

# IP público da tarefa Fargate (vazio se ainda não há tarefa rodando)
_qc_ip_tarefa() {
  local task eni
  task="$(aws ecs list-tasks --cluster "$ECS_CLUSTER" --service-name produtos-api \
            --desired-status RUNNING --query 'taskArns[0]' --output text 2>/dev/null)"
  [ -n "$task" ] && [ "$task" != "None" ] || return 1
  eni="$(aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$task" \
          --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" --output text)"
  [ -n "$eni" ] && [ "$eni" != "None" ] || return 1
  aws ec2 describe-network-interfaces --network-interface-ids "$eni" \
    --query 'NetworkInterfaces[0].Association.PublicIp' --output text 2>/dev/null | grep -v None
}

_qc_ajuda() {
  cat <<'AJUDA'
Uso: qc <comando>

  qc status                  o que está no ar (bucket, função, URL, ECR, tarefa)
  qc publica v1              Lab 1: publica a versão mock na Lambda
  qc publica v2              Lab 2: publica a versão que lê o catálogo no S3
  qc chama "/produtos?..."   chama a ferramenta pela Function URL
  qc container               Lab 3: build, push para o ECR e a tarefa no Fargate
  qc compara "/produtos?..." Lab 3: a mesma chamada na Lambda e no container

Exemplos:
  qc chama /produtos
  qc chama "/produtos?categoria=moveis&preco_max=1500"

Sessão nova do CloudShell? Rode de novo:
  source ~/aie-cloud/aulas/03-serverless-containers/lab/qc.sh
AJUDA
}

_qc_status() {
  echo "Bucket    : ${BUCKET_NAME:-VAZIO}"
  echo "Função    : ${FUNCTION_NAME:-VAZIO}"
  echo "URL       : ${FUNCTION_URL:-VAZIO}"
  echo "ECR       : ${ECR_URL:-VAZIO}"
  echo "Cluster   : ${ECS_CLUSTER:-VAZIO}"
  if [ -z "$FUNCTION_NAME" ]; then
    echo
    echo "AVISO: outputs vazios. O terraform apply terminou? Confira com:" >&2
    echo "       terraform -chdir=$_qc_tf output" >&2
  fi
}

_qc_publica() {
  local pasta
  case "${1:-}" in
    v1) pasta="v1-mock" ;;
    v2) pasta="v2-s3" ;;
    *) echo "Uso: qc publica v1 | v2" >&2; return 1 ;;
  esac
  _qc_precisa FUNCTION_NAME || return 1
  local zip="/tmp/qc-$pasta.zip"
  rm -f "$zip"
  # zip feito DE DENTRO da pasta: o lambda_function.py fica na raiz do pacote
  (cd "$QC_LAB/function/$pasta" && zip -qr "$zip" . -x '__pycache__/*' '*.pyc') || return 1
  echo "→ Publicando function/$pasta em $FUNCTION_NAME"
  aws lambda update-function-code --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$zip" --query 'LastModified' --output text >/dev/null || return 1
  aws lambda wait function-updated --function-name "$FUNCTION_NAME" || return 1
  echo "✓ $pasta publicada. Teste com: qc chama /produtos"
  echo "  Console: Lambda → $FUNCTION_NAME → Code (o código que acabou de subir)"
}

_qc_chama() {
  _qc_precisa FUNCTION_URL || return 1
  local url corpo saida st t
  url="${FUNCTION_URL%/}$(_qc_caminho "$1")"
  corpo="$(mktemp)"
  saida="$(_qc_get "$url" "$corpo")"
  st="${saida% *}"; t="${saida#* }"
  _qc_json "$corpo"
  rm -f "$corpo"
  echo
  echo "HTTP $st em ${t}s · $url"
  echo "Abra no navegador e no celular: ${FUNCTION_URL}"
  echo "A 1ª chamada depois de publicar é mais lenta (cold start): veja o Init Duration no CloudWatch."
}

_qc_container() {
  _qc_precisa ECR_URL ECS_CLUSTER || return 1
  local tag="${QC_IMAGE_TAG:-v1}"
  echo "→ 1/4 Build da imagem no CloudShell ($ECR_URL:$tag)"
  (cd "$QC_LAB/docker" && docker build --platform linux/amd64 -q -t "$ECR_URL:$tag" .) || return 1
  echo "→ 2/4 Login no ECR (credencial da sessão, sem senha)"
  aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_URL%%/*}" >/dev/null || return 1
  echo "→ 3/4 Push para o ECR"
  docker push -q "$ECR_URL:$tag" || return 1
  echo "→ 4/4 terraform apply com o serviço no Fargate (1 a 3 min)"
  terraform -chdir="$_qc_tf" apply -auto-approve -input=false \
    -var="ecs_enabled=true" -var="image_tag=$tag" >/tmp/qc-apply-ecs.log 2>&1 || {
      echo "ERRO no apply. Últimas linhas de /tmp/qc-apply-ecs.log:" >&2
      tail -15 /tmp/qc-apply-ecs.log >&2; return 1; }
  echo "→ Aguardando a tarefa ganhar IP público (até 5 min)"
  local ip="" i
  for i in $(seq 1 30); do
    ip="$(_qc_ip_tarefa)" && [ -n "$ip" ] && break
    sleep 10
  done
  if [ -z "$ip" ]; then
    echo "A tarefa não ficou RUNNING em 5 min. Veja: ECS → Clusters → $ECS_CLUSTER → Tasks (aba Logs)" >&2
    return 1
  fi
  export QC_CONTAINER_URL="http://$ip:8080"
  echo "✓ Container no ar: $QC_CONTAINER_URL/produtos"
  echo "  Console: ECR → produtos-api (a imagem e o tamanho) · ECS → $ECS_CLUSTER → Tasks"
  echo "  Agora: qc compara \"/produtos?categoria=moveis&preco_max=1500\""
}

_qc_compara() {
  _qc_precisa FUNCTION_URL ECS_CLUSTER || return 1
  local caminho ip lam con c1 c2 s1 s2
  caminho="$(_qc_caminho "$1")"
  ip="$(_qc_ip_tarefa)"
  if [ -z "$ip" ]; then
    echo "Não achei tarefa rodando no Fargate. Rode antes: qc container" >&2
    return 1
  fi
  lam="${FUNCTION_URL%/}$caminho"
  con="http://$ip:8080$caminho"
  c1="$(mktemp)"; c2="$(mktemp)"
  s1="$(_qc_get "$lam" "$c1")"; s2="$(_qc_get "$con" "$c2")"
  python3 - "$c1" "$c2" "$s1" "$s2" "$lam" "$con" <<'PY'
import json, sys
c1, c2, s1, s2, u1, u2 = sys.argv[1:7]
def resumo(arq):
    try:
        d = json.load(open(arq))
        return d.get("total", "?"), [p["nome"] for p in d.get("produtos", [])]
    except Exception:
        return "erro", []
for nome, arq, st, url in (("LAMBDA", c1, s1, u1), ("FARGATE", c2, s2, u2)):
    http, t = st.split()
    total, nomes = resumo(arq)
    print(f"{nome:<8} HTTP {http} · {float(t)*1000:.0f} ms · {total} produto(s)")
    print(f"         {url}")
    for n in nomes:
        print(f"           - {n}")
r1, r2 = resumo(c1)[1], resumo(c2)[1]
print()
if r1 == r2:
    print("Mesma resposta nas duas casas.")
else:
    print("ATENÇÃO: as respostas são diferentes. O filtro preco_max do Lab 2 está na v2 publicada?")
PY
  rm -f "$c1" "$c2"
  echo
  echo "Repare: HTTPS na Lambda, IP e porta no Fargate. Rode de novo e compare os tempos."
  echo "Pergunta: o que vocês ganharam com o container, e o que passaram a pagar?"
}

# ---------------------------------------------------------------------------
# O comando qc
# ---------------------------------------------------------------------------
qc() {
  case "${1:-}" in
    status)    _qc_carrega; _qc_status ;;
    publica)   _qc_publica "${2:-}" ;;
    chama)     _qc_chama "${2:-/produtos}" ;;
    container) _qc_container ;;
    compara)   _qc_compara "${2:-/produtos}" ;;
    ""|ajuda|help|-h|--help) _qc_ajuda ;;
    *) echo "Comando desconhecido: $1" >&2; _qc_ajuda; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
_qc_status
echo
echo "Pronto: digite  qc  para ver os comandos do lab."
