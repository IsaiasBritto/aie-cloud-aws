# Guia de Laboratório — Aula 4
## Serviços de IA da AWS & APIs

**Disciplina:** Cloud & Cognitive Environments
**MBA:** AI Engineering & Multi-Agents — FIAP
**Plataforma:** Amazon Web Services (AWS Academy Learner Lab)
**Ambiente:** **AWS CloudShell** — tudo no browser · região `us-east-1`

---

## Visão geral do lab

```
Abertura     — limpeza da Aula 3 + pré-voo dos serviços + terraform apply        ~10 min
Atividade 1  — semear reviews no DynamoDB                                         ~20 min  (L₁)
Atividade 2  — Polly (texto → fala) e Transcribe (fala → texto) via Lambda       ~30 min  (L₂)
Atividade 3  — Comprehend: pipeline de reviews (sentimento + entidades)          ~20 min  (L₃)
Atividade 4  — Rekognition: rótulos, objetos e texto de imagem de produto        ~15 min  (L₄)
Demo         — QC Cognitive Studio (Streamlit): duas arquiteturas, professor      ~10 min
Wrap-up      — terraform destroy + verificação de custo                           ~5 min
```

Os tempos casam com o roteiro do deck (slide 2). Os blocos de teoria acontecem entre as atividades.

> **Na AWS os serviços de IA não precisam de recurso provisionado:** Transcribe, Polly, Comprehend e Rekognition são APIs da conta, liberadas por IAM. O Terraform sobe só o que é seu: bucket, Lambda e a tabela DynamoDB das reviews.

> **Nenhuma credencial no lab inteiro:** a Lambda e o CloudShell falam com S3, DynamoDB e os serviços de IA pela LabRole. Não existe senha de banco, porta aberta nem chave de API — é a vacina da Aula 3 levada até o fim.

> **Regra de ouro:** `terraform destroy` ao final. Os serviços de IA e o DynamoDB on-demand cobram por chamada — sem chamadas, sem custo.

---

## Abertura — limpeza da Aula 3, pré-voo e apply (10 min)

**A Aula 3 foi destruída?** Tag Editor (região `us-east-1`, *All supported resource types*, tag `aula = 3`) deve voltar **vazio**. Se sobrou algo: `cd ~/aie-cloud/aulas/03-serverless-containers/lab/terraform && terraform destroy -auto-approve`.

```bash
# Ainda não clonou? Clone:
cd ~ && git clone https://github.com/IsaiasBritto/aie-cloud-aws.git aie-cloud

# Já clonou? Atualize SEM apagar a pasta (apagar leva junto o terraform.tfstate das aulas anteriores):
git -C ~/aie-cloud stash && git -C ~/aie-cloud pull

cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab

# Pré-voo: a sessão chega a S3, Lambda, DynamoDB, Polly, Transcribe, Comprehend e Rekognition?
bash check_servicos.sh

# Terraform no $HOME (se não instalou) e o apply
bash ~/aie-cloud/aulas/01-fundamentos-iac/lab/install_terraform.sh
export PATH="$HOME/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

cd terraform
terraform init
terraform apply -auto-approve
```

---

## Atividade 1 — Semear as reviews (L₁)

### Passo 1 — O que o Terraform criou

Enquanto o Terraform trabalha (~1 a 2 min), leia os arquivos:

| Arquivo | O que define |
|---------|--------------|
| [main.tf](terraform/main.tf) | Providers, tags, locals, data source da LabRole |
| [variables.tf](terraform/variables.tf) | `region` (padrão `us-east-1`) |
| [outputs.tf](terraform/outputs.tf) | Todos os outputs consumidos pelo guia e pelos scripts |
| [storage.tf](terraform/storage.tf) | Bucket de dados (módulo [`modulos/bucket-s3`](../../../modulos/bucket-s3/main.tf)) + prefixos `audios/` e `imagens/` |
| [lambda.tf](terraform/lambda.tf) | Lambda Python 3.12 + Function URL + LabRole (timeout 60 s) |
| (nenhum) | Nada a criar: Transcribe, Polly, Comprehend e Rekognition são APIs da conta |
| [dynamodb.tf](terraform/dynamodb.tf) | Tabela on-demand `reviews` (partição `produto`, ordenação `id`) |

### Passo 2 — Exportar os outputs

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab
source exportar-outputs.sh
```

> Abriu um terminal novo? Rode `source exportar-outputs.sh` de novo — as variáveis não sobrevivem à sessão.

### Passo 3 — Semear reviews no DynamoDB

```bash
# (de dentro de lab/; o exportar-outputs.sh já exportou REVIEWS_TABLE)
python3 scripts/semear_reviews.py
```

Console: **DynamoDB** → Tables → `qc-aula04-xxxxxx-reviews` → **Explore table items**.

> **Para discutir:** procure no [`semear_reviews.py`](scripts/semear_reviews.py) uma senha, um host, uma porta, uma chave. Não há. Quem autoriza a gravação? Compare com um banco autogerenciado numa EC2, que exigiria senha no cliente e porta aberta para a Lambda (exercício 1.3).

**✅ Checkpoint L₁:** 10 reviews na tabela?

---

## Atividade 2 — Texto → fala e fala → texto (L₂)

### Passo 1 — Gerar um áudio com o Amazon Polly

```bash
# Sem chave: o boto3 usa a credencial do CloudShell (LabRole)
aws sts get-caller-identity --query Arn --output text

python3 scripts/gerar_audio_tts.py      # → /tmp/audio-teste.mp3
```

### Passo 2 — Copiar os áudios para o bucket

```bash
echo "Data Bucket: $DATA_BUCKET"

aws s3 cp /tmp/audio-teste.mp3 s3://$DATA_BUCKET/audios/audio-teste.mp3

# Um trecho real de podcast da BBC Brasil (já no repositório)
aws s3 cp ~/aie-cloud/aulas/04-servicos-cognitivos/lab/data/bbc_exemplo.mp3 \
  s3://$DATA_BUCKET/audios/bbc_exemplo.mp3
```

> **Challenge:** o formato do áudio vem da extensão do arquivo. E com um `.m4a`?

### Passo 3 — Deploy da Lambda

```bash
echo "Lambda: $FUNC_NAME"
cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab/function

# Empacota COM as dependências (a Lambda não instala o requirements.txt sozinha).
# Os flags baixam pacotes compilados para o Python 3.12 da Lambda — o CloudShell tem outro Python.
rm -rf pacote && mkdir pacote
pip install -r requirements.txt -t pacote -q \
  --platform manylinux2014_x86_64 --python-version 3.12 --only-binary=:all:
cp function_app.py pacote/
(cd pacote && zip -qr /tmp/function.zip .)
aws lambda update-function-code --function-name "$FUNC_NAME" --zip-file fileb:///tmp/function.zip
aws lambda wait function-updated --function-name "$FUNC_NAME"
```

Explore o [function_app.py](function/function_app.py): as rotas `health` e `transcrever` (Lab 2), `analisar-reviews` (Lab 3) e `analisar-imagem` (Lab 4). Desta vez o roteamento usa o **Powertools for AWS Lambda**: o mesmo decorator `@app.get(...)` do FastAPI da Aula 3, agora dentro da Lambda.

### Passo 4 — Transcrever

```bash
curl -s "${FUNC_URL}health" | python3 -m json.tool

curl -s -X POST "${FUNC_URL}transcrever?arquivo=audio-teste.mp3&idioma=pt-BR" | python3 -m json.tool
curl -s -X POST "${FUNC_URL}transcrever?arquivo=bbc_exemplo.mp3" | python3 -m json.tool
```

O Transcribe é **assíncrono**: a rota inicia um job e espera ele terminar (áudios curtos levam ~10-20 s). Áudio longo devolve `IN_PROGRESS` com o nome do job — consulte depois com `aws transcribe get-transcription-job`.

> **Conexão com a Aula 3 — "na Lambda, você paga a espera":** esta rota passa até 50 s consultando o job a cada 2 s, com a CPU parada, e paga por todo esse tempo. Em produção, a Lambda só iniciaria o job; o Transcribe grava o resultado no S3 e um evento (S3 ou EventBridge) dispara outra Lambda, que roda só quando o resultado está pronto.

> ⚠️ **Esperado, não é falha:** a primeira chamada leva ~1-2 s a mais (cold start).

**✅ Checkpoint L₂:** a transcrição do `audio-teste.mp3` volta em português?

---

## Atividade 3 — Comprehend: pipeline de reviews (L₃)

### Passo 1 — Analisar as reviews

```bash
echo "URL para avaliar reviews: ${FUNC_URL}analisar-reviews?limit=10"
curl -s -X POST "${FUNC_URL}analisar-reviews?limit=10" | python3 -m json.tool
```

A rota lê do DynamoDB as reviews **sem** o atributo `sentimento` (`attribute_not_exists(sentimento)` — evita reprocessar e pagar de novo), roda `batch_detect_sentiment` e `batch_detect_entities` do Comprehend em lotes de até 25, e grava o resultado de volta em cada item.

> **Lembra do Query × Scan da Aula 2?** Para achar as pendentes, a rota faz um **Scan** com filtro: lê a tabela inteira. Com 10 reviews, tudo bem. Com 10 milhões, cada chamada paga a tabela toda. Em produção: um gatilho do **DynamoDB Streams** analisa cada review no momento em que ela é gravada.

Rode de novo: a resposta é "Nenhuma review nova para analisar" — o filtro funcionou.

### Passo 2 — Validar no console

**DynamoDB** → a tabela → **Explore table items**: cada item ganhou `sentimento`, `sentimento_score` e `entidades`.

**✅ Checkpoint L₃:** a distribuição de sentimentos bate com as estrelas das reviews?

---

## Atividade 4 — Rekognition: imagem de produto (L₄)

### Passo 1 — Upload da imagem

```bash
aws s3 cp ~/aie-cloud/aulas/04-servicos-cognitivos/lab/data/produto.jpg \
  s3://$DATA_BUCKET/imagens/produto.jpg
```

### Passo 2 — Analisar

```bash
echo "URL para analisar imagem: ${FUNC_URL}analisar-imagem?arquivo=produto.jpg"
curl -s "${FUNC_URL}analisar-imagem?arquivo=produto.jpg" | python3 -m json.tool
```

A resposta traz `tags` (rótulos com confiança), `objetos` (rótulos com caixa — em proporção da imagem, de 0 a 1) e `texto` (o que o Rekognition leu na imagem).

**✅ Checkpoint L₄:** o Rekognition reconheceu o produto e leu o texto da imagem?

---

## Demo — QC Cognitive Studio: duas arquiteturas (professor, ~10 min)

**Objetivo:** ver os serviços numa interface e comparar **duas arquiteturas de acesso à IA**, com o mesmo resultado e riscos completamente diferentes.

O professor roda o app [Streamlit](app/README.md) na própria máquina (o navegador só libera o microfone em `localhost` ou HTTPS) e mostra:

1. **Via Lambda:** só a Function URL preenchida, nenhuma credencial no app — Polly, Transcribe e Rekognition respondem.
2. **Direto na AWS:** o app usa uma access key na barra lateral para chamar os serviços sem passar pela Lambda.
3. **Comparar os dois:** os resultados são iguais; o caminho direto é mais rápido, porque tem um salto a menos.

| | Via Lambda | Direto na AWS |
|---|---|---|
| Credencial no cliente | não existe | access key |
| Quem se autentica | a função, com a LabRole | quem tiver a chave |
| Se o código do cliente vazar | só a URL da função | a credencial vai junto |
| Latência | um salto a mais | um salto a menos |

**A pergunta que fecha a aula:** se o caminho direto é mais rápido e mais simples, por que a arquitetura da disciplina insiste no outro?

> **Opcional para o aluno:** o app roda no seu notebook (`pip install -r requirements.txt && streamlit run app.py`), fora da política "nada instalado". As instruções completas estão no [README do app](app/README.md).

---

## Wrap-up — Destroy e custo zero (5 min)

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab/terraform
terraform destroy -auto-approve
```

**Conferir:** Tag Editor com a tag `aula = 4` → a busca deve voltar **vazia**; e o crédito consumido na página do Learner Lab. Os jobs do Transcribe ficam listados no console por 90 dias, mas não cobram nada depois de concluídos.

---

## Conexão com o projeto Quantum Commerce

A Lambda da QC agora tem **tools de IA**:

```
GET  /health                              ← status
POST /transcrever?arquivo=...&idioma=...  ← Transcribe (atendimento por voz)
POST /analisar-reviews?limit=N            ← Comprehend (sentimento das reviews)
GET  /analisar-imagem?arquivo=...         ← Rekognition (busca visual de produtos)
```

Somadas à tool de catálogo da Aula 3 (`GET /produtos`, em outra Lambda), são quatro tools. Os agentes podem: buscar produtos, ouvir o cliente no atendimento por voz, entender o sentimento das reviews para recomendar produtos e analisar a foto que o cliente enviou para achar o produto.

---

## Troubleshooting

| Problema | Causa | Solução |
|----------|-------|---------|
| `AccessDenied ... GetBucketObjectLockConfiguration` no `terraform apply` | O Learner Lab bloqueia essa leitura, que o `aws_s3_bucket` faz sempre. Os labs agora criam o bucket pelo módulo `modulos/bucket-s3` (AWS CLI) | `git -C ~/aie-cloud pull`, `terraform init`, `terraform state rm aws_s3_bucket.data` e `terraform apply` de novo. O módulo reaproveita o bucket que já foi criado |
| `{"status": "placeholder"}` em qualquer rota | O código real ainda não foi publicado | Passo 3 da Atividade 2 |
| `Runtime.ImportModuleError: No module named 'aws_lambda_powertools'` | O zip foi feito sem as dependências | Refaça o Passo 3 (pasta `pacote/` com `pip install -t` e os flags de plataforma) |
| `403 Forbidden` na Function URL | Falta uma das duas permissões da URL pública | `terraform apply` de novo; `aws lambda get-policy --function-name "$FUNC_NAME"` |
| `/transcrever` → `BadRequestException ... media format` | Extensão diferente do formato real do áudio | Renomeie o arquivo ou converta |
| `/transcrever` → `IN_PROGRESS` | Áudio longo para os 60 s da Lambda | `aws transcribe get-transcription-job --transcription-job-name <job>` |
| `/analisar-reviews` → `ResourceNotFoundException` | A Lambda não achou a tabela | `terraform apply` de novo; confira `REVIEWS_TABLE` em Lambda → Configuration → Environment variables |
| `/analisar-reviews` → "Nenhuma review nova" | Todas já analisadas | Correto — rode `semear_reviews.py` para reinserir (o `put_item` zera a análise) |
| `semear_reviews.py` → "Exporte REVIEWS_TABLE" | Sessão nova do CloudShell | `source exportar-outputs.sh` |
| `check_servicos.sh` com ✗ | Sessão do Learner Lab expirada, ou serviço fora do Learner Lab | **Start Lab** e CloudShell novo; se persistir, avise o professor antes do lab |
| `AccessDeniedException` no Comprehend/Rekognition | Sessão do Learner Lab expirou | **Start Lab** e CloudShell novo |

---

## Tarefa pós-aula

1. Atualizar o `entrega-grupo-aula04.md` com:
   - Trecho da transcrição em PT-BR
   - Distribuição de sentimentos das 10 reviews
   - JSON de uma análise de imagem de produto
   - Diagrama da arquitetura QC com a camada de IA
2. Resolver pelo menos N1 + N2 dos exercícios

---

## Referências

- [Amazon Transcribe — jobs em lote](https://docs.aws.amazon.com/transcribe/latest/dg/batch-med-transcription.html)
- [Amazon Polly — vozes disponíveis](https://docs.aws.amazon.com/polly/latest/dg/available-voices.html)
- [Amazon Comprehend — idiomas suportados](https://docs.aws.amazon.com/comprehend/latest/dg/supported-languages.html)
- [Amazon Rekognition — rótulos e texto](https://docs.aws.amazon.com/rekognition/latest/dg/labels.html)
- [Powertools for AWS Lambda (Python) — Event Handler](https://docs.powertools.aws.dev/lambda/python/latest/core/event_handler/api_gateway/)
- [Pacotes .zip de Lambda com dependências](https://docs.aws.amazon.com/lambda/latest/dg/python-package.html)
