#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Atalhos do lab da Aula 4. Carregue UMA vez por sessão do CloudShell,
# depois do terraform apply:
#
#   source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/qc.sh
#
# O que o source faz:
#   - exporta os outputs do Terraform que os comandos usam;
#   - cria o comando `qc` (rode `qc` sem nada para ver a ajuda).
#
# O CloudShell encerra a sessão depois de ~20 min sem uso: rode o source de
# novo e está tudo de volta (o estado do Terraform fica no $HOME).
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
# O Terraform recusa um cache que não existe (ex.: depois de limpar o $HOME)
mkdir -p "$TF_PLUGIN_CACHE_DIR"

_qc_carrega() {
  # Sem state (antes do apply ou depois do destroy), o terraform imprime
  # "No outputs found" na saída padrão: vira vazio.
  _qc_out() {
    local v
    v="$(terraform -chdir="$_qc_tf" output -raw "$1" 2>/dev/null)" || v=""
    case "$v" in *$'\n'*|*"No outputs found"*|*"╷"*) v="" ;; esac
    printf '%s' "$v"
  }
  DATA_BUCKET="$(_qc_out data_bucket_name)"
  FUNC_NAME="$(_qc_out lambda_name)"
  FUNC_URL="$(_qc_out function_url)"
  REVIEWS_TABLE="$(_qc_out reviews_table)"
  PRODUTOS_TABLE="$(_qc_out produtos_table)"
  SECRET_NAME="$(_qc_out secret_name)"
  export DATA_BUCKET FUNC_NAME FUNC_URL REVIEWS_TABLE PRODUTOS_TABLE SECRET_NAME
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

# JSON legível, com acentos
_qc_json() {
  python3 -c 'import json,sys
t=open(sys.argv[1]).read()
try: print(json.dumps(json.loads(t), ensure_ascii=False, indent=2))
except Exception: print(t)' "$1"
}

# _qc_post CAMINHO [corpo-json]: chama a Function URL e mostra a resposta
_qc_post() {
  _qc_precisa FUNC_URL || return 1
  local url="${FUNC_URL%/}$1" corpo saida
  corpo="$(mktemp)"
  if [ -n "${2:-}" ]; then
    saida="$(curl -s -m 70 -X POST -H 'content-type: application/json' -d "$2" \
               -o "$corpo" -w '%{http_code} %{time_total}' "$url")"
  else
    saida="$(curl -s -m 70 -X POST -o "$corpo" -w '%{http_code} %{time_total}' "$url")"
  fi
  _qc_json "$corpo"
  rm -f "$corpo"
  echo
  echo "HTTP ${saida% *} em ${saida#* }s · POST $url"
}

# _qc_sobe ARQUIVO PREFIXO: manda um arquivo (do data/ ou caminho seu) ao bucket
_qc_sobe() {
  local origem="$1" prefixo="$2" nome
  [ -f "$origem" ] || origem="$QC_LAB/data/$1"
  if [ ! -f "$origem" ]; then
    echo "ERRO: arquivo $1 não encontrado (nem em $QC_LAB/data/)" >&2
    return 1
  fi
  nome="$(basename "$origem")"
  aws s3 cp "$origem" "s3://$DATA_BUCKET/$prefixo/$nome" --quiet || return 1
  echo "→ $nome enviado para s3://$DATA_BUCKET/$prefixo/" >&2
  printf '%s' "$nome"
}

_qc_ajuda() {
  cat <<'AJUDA'
Uso: qc <comando>

  qc status                       o que está no ar (bucket, função, tabelas, segredo)
  qc publica                      empacota a Lambda com as dependências e publica

  Lab 1 · reviews
  qc semeia                       grava 10 reviews no DynamoDB

  Lab 2 · voz pela API de IA da QC
  qc chave                        guarda URL + chave do grupo no Secrets Manager
  qc fala "texto" [voz]           texto → fala (MP3 no bucket, com link para ouvir)
  qc transcreve [arquivo]         fala → texto (padrão: o último qc fala)

  Lab 3 · ler
  qc reviews                      sentimento das reviews pendentes (API de IA)
  qc documento [etiqueta.png]     Textract: OCR puro × campos do formulário

  Lab 4 · ver
  qc catalogo [produto.jpg]       Rekognition: tags do produto no catálogo
  qc foto-review ID [arquivo]     anexa uma foto à review; a moderação roda por evento
  qc tabela reviews|produtos      o que está gravado no DynamoDB

Sessão nova do CloudShell? Rode de novo:
  source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/qc.sh
AJUDA
}

_qc_status() {
  local seg="não"
  [ -n "$SECRET_NAME" ] && aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" \
      --query Name --output text >/dev/null 2>&1 && seg="sim"
  echo "Bucket    : ${DATA_BUCKET:-VAZIO}"
  echo "Função    : ${FUNC_NAME:-VAZIO}"
  echo "URL       : ${FUNC_URL:-VAZIO}"
  echo "Tabelas   : ${REVIEWS_TABLE:-VAZIO} · ${PRODUTOS_TABLE:-VAZIO}"
  echo "Segredo   : ${SECRET_NAME:-VAZIO} (chave gravada: $seg)"
  if [ -z "$FUNC_NAME" ]; then
    echo
    echo "AVISO: outputs vazios. O terraform apply terminou? Confira com:" >&2
    echo "       terraform -chdir=$_qc_tf output" >&2
  fi
}

_qc_publica() {
  _qc_precisa FUNC_NAME || return 1
  # Pacote em /tmp: o $HOME do CloudShell tem só 1 GB e guarda o repositório e os tfstate
  local pac=/tmp/qc-pacote zip=/tmp/qc-funcao.zip
  rm -rf "$pac" "$zip" && mkdir -p "$pac"
  echo "→ 1/3 Dependências para o Python 3.12 da Lambda (o CloudShell tem outro Python)"
  pip install -r "$QC_LAB/function/requirements.txt" -t "$pac" -q --disable-pip-version-check \
    --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all: || return 1
  cp "$QC_LAB/function/function_app.py" "$pac/"
  (cd "$pac" && zip -qr "$zip" . -x '__pycache__/*') || return 1
  echo "→ 2/3 Publicando $(du -k "$zip" | cut -f1) KB em $FUNC_NAME"
  aws lambda update-function-code --function-name "$FUNC_NAME" \
    --zip-file "fileb://$zip" --query LastModified --output text >/dev/null || return 1
  echo "→ 3/3 Esperando a função atualizar"
  aws lambda wait function-updated --function-name "$FUNC_NAME" || return 1
  echo "✓ Publicada. Teste: curl -s ${FUNC_URL}health"
}

_qc_semeia() {
  _qc_precisa REVIEWS_TABLE || return 1
  python3 "$QC_LAB/scripts/semear_reviews.py"
}

_qc_chave() {
  _qc_precisa SECRET_NAME || return 1
  local url chave
  echo "A URL e a chave do grupo foram entregues pelo professor (fora do repositório)."
  read -r -p "URL da API de IA: " url
  read -r -s -p "Chave do grupo (não aparece na tela): " chave; echo
  if [ -z "$url" ] || [ -z "$chave" ]; then
    echo "ERRO: URL e chave são obrigatórias." >&2; return 1
  fi
  # O valor vai direto para o Secrets Manager: não fica no código, no tfstate nem
  # no histórico do shell (o read não grava no history).
  aws secretsmanager put-secret-value --secret-id "$SECRET_NAME" \
    --secret-string "$(python3 -c 'import json,sys; print(json.dumps({"url": sys.argv[1], "chave": sys.argv[2]}))' "$url" "$chave")" \
    --query VersionId --output text >/dev/null || return 1
  unset chave
  echo "✓ Segredo gravado em $SECRET_NAME"
  echo "  Console: Secrets Manager → $SECRET_NAME → Retrieve secret value"
  echo "  Agora: qc fala \"Seu pedido saiu para entrega.\""
}

_qc_fala() {
  local texto="${1:-Olá! Aqui é a assistente da Quantum Commerce. Seu pedido saiu para entrega.}"
  local voz="${2:-Camila}" corpo
  corpo="$(python3 -c 'import json,sys; print(json.dumps({"texto": sys.argv[1], "voz": sys.argv[2]}, ensure_ascii=False))' "$texto" "$voz")"
  local saida; saida="$(mktemp)"
  _qc_post /falar "$corpo" | tee "$saida"
  QC_ULTIMA_FALA="$(python3 -c 'import json,sys
t=open(sys.argv[1]).read(); i=t.find("{"); j=t.rfind("}")
try: print(json.loads(t[i:j+1]).get("arquivo",""))
except Exception: pass' "$saida")"
  export QC_ULTIMA_FALA
  rm -f "$saida"
  [ -n "$QC_ULTIMA_FALA" ] && echo "Abra o link \"ouvir\" no navegador. Depois: qc transcreve"
}

_qc_transcreve() {
  _qc_precisa DATA_BUCKET || return 1
  local arq="${1:-$QC_ULTIMA_FALA}"
  if [ -z "$arq" ]; then
    echo "Uso: qc transcreve <arquivo>   (ex.: bbc_trecho.mp3, ou rode antes qc fala)" >&2
    return 1
  fi
  # Arquivo do data/ que ainda não está no bucket? Sobe antes
  if ! aws s3api head-object --bucket "$DATA_BUCKET" --key "audios/$arq" >/dev/null 2>&1; then
    arq="$(_qc_sobe "$arq" audios)" || return 1
  fi
  echo "→ Transcrevendo $arq (leva de 10 a 25 s: o Transcribe trabalha em job assíncrono)"
  _qc_post "/transcrever?arquivo=$arq&idioma=pt-BR"
}

_qc_reviews() {
  _qc_post "/analisar-reviews?limit=10"
  echo "Veja o resultado gravado: qc tabela reviews"
}

_qc_documento() {
  _qc_precisa DATA_BUCKET || return 1
  local arq; arq="$(_qc_sobe "${1:-etiqueta.png}" documentos)" || return 1
  local saida; saida="$(mktemp)"
  _qc_post "/ler-documento?arquivo=$arq" >"$saida"
  python3 - "$saida" <<'PY'
import json, sys
t = open(sys.argv[1]).read(); i = t.find("{"); j = t.rfind("}")
try:
    d = json.loads(t[i:j + 1])
except Exception:
    print(t); sys.exit()
if "erro" in d:
    print(json.dumps(d, ensure_ascii=False, indent=2)); sys.exit()
print("OCR (detect_document_text): linhas soltas, sem saber o que é o quê")
for l in d["ocr_linhas"]:
    print(f"   {l}")
print("\nFORMULÁRIO (analyze_document FORMS): campo → valor")
for c in d["campos"]:
    print(f"   {c['campo']:<18} → {c['valor']:<32} ({c['confianca']}%)")
PY
  tail -1 "$saida"; rm -f "$saida"
}

_qc_catalogo() {
  _qc_precisa DATA_BUCKET || return 1
  local arq; arq="$(_qc_sobe "${1:-produto.jpg}" imagens)" || return 1
  _qc_post "/analisar-imagem?arquivo=$arq&produto=${2:-${arq%.*}}"
}

_qc_foto_review() {
  _qc_precisa DATA_BUCKET FUNC_NAME || return 1
  local id="$1" arq="${2:-review-foto-praia.jpg}" origem ext
  if [ -z "$id" ]; then
    echo "Uso: qc foto-review <id da review> [arquivo]   (ex.: qc foto-review r004)" >&2
    return 1
  fi
  origem="$arq"; [ -f "$origem" ] || origem="$QC_LAB/data/$arq"
  [ -f "$origem" ] || { echo "ERRO: $arq não encontrado" >&2; return 1; }
  ext="${origem##*.}"
  # Zera o status anterior, para não ler o resultado de uma rodada antiga
  local produto
  produto="$(aws dynamodb scan --table-name "$REVIEWS_TABLE" --filter-expression "id = :i" \
              --expression-attribute-values "{\":i\":{\"S\":\"$id\"}}" --query 'Items[0].produto.S' --output text)"
  if [ -z "$produto" ] || [ "$produto" = "None" ]; then
    echo "ERRO: a review $id não existe. Rode qc semeia e confira com qc tabela reviews" >&2
    return 1
  fi
  aws dynamodb update-item --table-name "$REVIEWS_TABLE" \
    --key "{\"produto\":{\"S\":\"$produto\"},\"id\":{\"S\":\"$id\"}}" \
    --update-expression "REMOVE foto_status, foto_motivos" >/dev/null
  # O nome do objeto é o id da review: é assim que a função acha a review
  aws s3 cp "$origem" "s3://$DATA_BUCKET/reviews-fotos/$id.$ext" --quiet || return 1
  echo "→ Foto enviada para reviews-fotos/$id.$ext."
  # Numa conta normal, o upload já dispara a função (o evento está no storage.tf).
  # O Learner Lab não entrega eventos do S3 (nem direto, nem pelo EventBridge):
  # aqui o qc faz o papel do S3 e entrega à função o MESMO evento, de forma
  # assíncrona (--invocation-type Event): ninguém espera a resposta.
  local ev; ev="$(mktemp)"
  printf '{"Records":[{"eventSource":"aws:s3","eventName":"ObjectCreated:Put","s3":{"bucket":{"name":"%s"},"object":{"key":"reviews-fotos/%s.%s"}}}]}' \
    "$DATA_BUCKET" "$id" "$ext" > "$ev"
  aws lambda invoke --function-name "$FUNC_NAME" --invocation-type Event \
    --cli-binary-format raw-in-base64-out --payload "file://$ev" /dev/null \
    --query StatusCode --output text >/dev/null || { rm -f "$ev"; return 1; }
  rm -f "$ev"
  echo "→ Evento entregue à função (assíncrono: HTTP 202, sem resposta). Você não esperou a moderação."
  echo "→ Conferindo a tabela até a moderação aparecer..."
  local st=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 3
    st="$(aws dynamodb scan --table-name "$REVIEWS_TABLE" --filter-expression "id = :i" \
          --expression-attribute-values "{\":i\":{\"S\":\"$id\"}}" \
          --query 'Items[0].foto_status.S' --output text 2>/dev/null)"
    [ -n "$st" ] && [ "$st" != "None" ] && break
  done
  if [ -z "$st" ] || [ "$st" = "None" ]; then
    echo "Sem resultado na tabela em 30 s. Veja o log da função:" >&2
    echo "  aws logs tail /aws/lambda/$FUNC_NAME --since 5m" >&2
    return 1
  fi
  aws dynamodb scan --table-name "$REVIEWS_TABLE" --filter-expression "id = :i" \
    --expression-attribute-values "{\":i\":{\"S\":\"$id\"}}" \
    --query 'Items[0].{review:id.S,produto:produto.S,foto:foto.S,status:foto_status.S,motivos:foto_motivos.L[].S}' \
    --output json
  # O log chega ao CloudWatch alguns segundos depois da gravação na tabela:
  # procura a linha DESTA review, tentando por até ~15 s
  echo "O que o Rekognition viu (log da função):"
  local linha=""
  for _ in 1 2 3 4 5; do
    linha="$(aws logs tail "/aws/lambda/$FUNC_NAME" --since 5m --format short 2>/dev/null \
              | grep "\"review\":\"$id\"" | tail -1)"
    [ -n "$linha" ] && break
    sleep 3
  done
  if [ -z "$linha" ]; then
    echo "  (o log ainda não chegou; veja depois: aws logs tail /aws/lambda/$FUNC_NAME --since 5m)"
  else
    printf '%s' "$linha" | python3 -c 'import json,sys
t=sys.stdin.read(); d=json.loads(t[t.index("{"):])
rs=d.get("rotulos") or []
if not rs: print("  nenhum rótulo de moderação acima de 60% de confiança")
for r in rs: print("  %-55s %5.1f%%  (categoria: %s)" % (r["rotulo"], r["confianca"], r["categoria"]))'
  fi
}

_qc_tabela() {
  case "${1:-reviews}" in
    reviews)
      _qc_precisa REVIEWS_TABLE || return 1
      aws dynamodb scan --table-name "$REVIEWS_TABLE" --output json \
        --query 'Items[].{id:id.S,estrelas:estrelas.N,sentimento:sentimento.S,foto:foto_status.S,produto:produto.S}' \
        | python3 -c 'import json,sys
for i in sorted(json.load(sys.stdin), key=lambda x: x["id"]):
    s = i["sentimento"] or "-"; f = i["foto"] or "-"
    print("%s  %s★  %-9s foto: %-10s %s" % (i["id"], i["estrelas"], s, f, i["produto"]))' ;;
    produtos)
      _qc_precisa PRODUTOS_TABLE || return 1
      aws dynamodb scan --table-name "$PRODUTOS_TABLE" --output json \
        --query 'Items[].{produto:produto.S,tags:tags.L[].S,texto:texto_na_imagem.S}' ;;
    *) echo "Uso: qc tabela reviews|produtos" >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# O comando qc
# ---------------------------------------------------------------------------
qc() {
  case "${1:-}" in
    status)      _qc_carrega; _qc_status ;;
    publica)     _qc_publica ;;
    semeia)      _qc_semeia ;;
    chave)       _qc_chave ;;
    fala)        _qc_fala "${2:-}" "${3:-}" ;;
    transcreve)  _qc_transcreve "${2:-}" ;;
    reviews)     _qc_reviews ;;
    documento)   _qc_documento "${2:-}" ;;
    catalogo)    _qc_catalogo "${2:-}" "${3:-}" ;;
    foto-review) _qc_foto_review "${2:-}" "${3:-}" ;;
    tabela)      _qc_tabela "${2:-}" ;;
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
