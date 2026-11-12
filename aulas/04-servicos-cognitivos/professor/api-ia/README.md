# API de IA da QC (conta do professor)

O Learner Lab não libera Polly, Transcribe nem Comprehend (a política da conta nega as ações, com qualquer sessão). Para os alunos usarem voz e sentimento na Aula 4, o professor publica esta API na própria conta AWS. As Lambdas dos alunos consomem como um serviço de terceiro: URL + API key do grupo, guardadas no Secrets Manager do Learner Lab.

```
Lambda do aluno (Learner Lab) ──x-api-key──► API Gateway (usage plan) ──► Lambda da API ──► Polly · Transcribe · Comprehend
```

| Rota | Corpo | Resposta |
|------|-------|----------|
| `POST /tts` | `{"texto": "...", "voz": "Camila"}` (`"formato": "wav"` opcional) | `{"audio_b64": "...", "formato": "mp3"}` |
| `POST /stt` | `{"audio_b64": "...", "formato": "mp3", "idioma": "pt-BR"}` | `{"status": "COMPLETED", "transcricao": "..."}` |
| `POST /sentimento` | `{"textos": ["...", "..."], "idioma": "pt"}` (até 25) | `{"resultados": [{"indice", "sentimento", "scores", "entidades"}]}` |
| `POST /visao` | `{"imagem_b64": "..."}` | rótulos, texto e objetos em pixels (usado só pelo app Streamlit da demo) |
| `GET /health` | | `{"status": "ok"}` |

Tudo em JSON: o áudio vai em base64 para não depender de tipos binários no API Gateway. Os limites vêm do caminho: 29 s de timeout do API Gateway (a transcrição espera até 24 s) e 4 MB de áudio por chamada.

## Proteções

| Proteção | Onde | Efeito |
|----------|------|--------|
| Uma API key por grupo | `var.grupos` | Vazou a chave de um grupo? Tire o nome da lista e `terraform apply`: só aquela para de funcionar |
| Cota diária por chave | `var.cota_diaria` (300) | O lab inteiro usa umas 30 chamadas; o resto devolve 429 |
| Limite de taxa | usage plan: 5 req/s, pico 10 | Um script em loop não derruba a turma |
| Teto de concorrência | `reserved_concurrent_executions = 20` | Mesmo com chave vazada, no máximo 20 execuções ao mesmo tempo |
| Menor privilégio | role própria | Só `polly:SynthesizeSpeech`, as três ações do Transcribe, as duas do Comprehend, duas do Rekognition e o bucket temporário |
| Alerta de custo | AWS Budget | E-mail em 50% e 100% de `var.orcamento_usd` (US$ 10) |

Custo de uma turma de 8 grupos fazendo o lab: centavos. O Polly neural cobra US$ 16 por milhão de caracteres; o Transcribe, US$ 0,024 por minuto de áudio; o Comprehend, US$ 0,0001 por unidade de 100 caracteres (mínimo de 3 unidades por texto).

## Publicar (na SUA conta, não no Learner Lab)

No CloudShell da sua conta, região `us-east-1`:

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/professor/api-ia/terraform
cp terraform.tfvars.example terraform.tfvars    # preencha o e-mail; o .gitignore exclui o .tfvars
terraform init
terraform apply
```

Depois do apply:

```bash
terraform output url                      # a URL, igual para todos
terraform output -json chaves             # uma chave por grupo: entregue cada uma ao seu grupo, fora do Git
```

Teste com a chave `professor`:

```bash
URL=$(terraform output -raw url)
CHAVE=$(terraform output -json chaves | python3 -c 'import json,sys; print(json.load(sys.stdin)["professor"])')
curl -s "$URL/health" -H "x-api-key: $CHAVE"
curl -s -X POST "$URL/sentimento" -H "x-api-key: $CHAVE" -H 'content-type: application/json' \
  -d '{"textos": ["Adorei o produto", "Chegou quebrado"], "idioma": "pt"}'
curl -s "$URL/health"     # sem chave: 403 do API Gateway, a Lambda nem é chamada
```

> Logo depois do apply, a chamada com chave pode devolver `{"message":"Forbidden"}` por um ou dois minutos: a associação das chaves ao usage plan leva esse tempo para valer. Espere e repita antes de investigar.

> O provider AWS do Terraform passa de 600 MB, e o `$HOME` do CloudShell tem 1 GB. Se o `init` der `no space left on device`, rode antes `export TF_PLUGIN_CACHE_DIR=/tmp/tf-cache TF_DATA_DIR=/tmp/tf-api-ia && mkdir -p /tmp/tf-cache`. O `terraform.tfstate` continua na pasta; só os providers vão para o `/tmp`, que some quando a sessão reinicia (repita o export e o `init` antes de um destroy).

## Durante a aula

Uso por grupo: **API Gateway → Usage plans → `qc-api-ia-...-turma` → Associated API keys → Usage**. O log da Lambda (`/aws/lambda/qc-api-ia-...`) traz o `api_key_id` de cada chamada; `terraform output chave_ids` diz de que grupo é cada id.

Revogar um grupo: tire o nome de `grupos` no `terraform.tfvars` e rode `terraform apply`. Trocar todas as chaves: `terraform apply -replace='aws_api_gateway_api_key.grupo["grupo-01"]'` (um por grupo) ou destroy e apply.

## Depois da disciplina

```bash
terraform destroy
```

O AWS Budget sai junto. Os jobs do Transcribe são apagados pela própria função a cada transcrição.
