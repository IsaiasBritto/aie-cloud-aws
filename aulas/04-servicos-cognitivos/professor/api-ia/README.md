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
EMAIL='seu@email.com'                           # troque pelo seu: recebe o alerta do budget de US$ 10
cp terraform.tfvars.example terraform.tfvars && sed -i "s/seu-email@exemplo.com/$EMAIL/" terraform.tfvars
cat terraform.tfvars                            # confira o e-mail
terraform init
terraform apply
```

O `terraform.tfvars` guarda o e-mail para o `apply`, o `destroy` e as republicações. O `.gitignore` exclui `*.tfvars`, então ele nunca vai para o Git. Se o arquivo já existe de uma publicação anterior, pule a linha do `cp`.

As linhas comentadas do arquivo são opcionais: sem elas, a API cria as chaves `grupo-01` a `grupo-08` e `professor`, com 300 chamadas por dia cada. Para outro número de grupos, acrescente a linha antes do `apply`:

```bash
echo 'grupos = ["grupo-01", "grupo-02", "grupo-03", "grupo-04", "grupo-05", "grupo-06", "professor"]' >> terraform.tfvars
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

### Recuperar a URL e as chaves depois que a sessão cai

A URL e as chaves não se perdem quando o CloudShell reinicia: o `terraform.tfstate` fica na pasta, no `$HOME`. O que some é o `/tmp`, onde estavam os providers. Abra o CloudShell de novo na sua conta, região `us-east-1`, e use um dos caminhos.

Pelo Terraform, refazendo o `init` em `/tmp` (cerca de 1 minuto):

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/professor/api-ia/terraform
export TF_PLUGIN_CACHE_DIR=/tmp/tf-cache TF_DATA_DIR=/tmp/tf-api-ia
mkdir -p "$TF_PLUGIN_CACHE_DIR" && terraform init -input=false >/dev/null
terraform output url
terraform output -json chaves
```

Só pela AWS CLI, sem `init`:

```bash
API=$(aws apigateway get-rest-apis --query "items[?starts_with(name,'qc-api-ia')].id" --output text)
echo "URL: https://$API.execute-api.us-east-1.amazonaws.com/v1"
aws apigateway get-api-keys --include-values \
  --query "items[?starts_with(name,'qc-api-ia')].[name,value]" --output table
```

Os dois mostram as chaves na tela: rode com o projetor desligado.

## Durante a aula

### Entregar URL e chave a cada grupo

Na pasta `terraform`, a lista de grupos com as chaves:

```bash
terraform output -json chaves | python3 -c '
import json, sys
chaves = json.load(sys.stdin)
print("URL:", sys.argv[1]); print()
for grupo in sorted(chaves):
    print(f"{grupo:<10}  {chaves[grupo]}")
' "$(terraform output -raw url)"
```

Ou uma mensagem pronta por grupo, para copiar e colar (a chave `professor` fica de fora):

```bash
terraform output -json chaves | python3 -c '
import json, sys
url, chaves = sys.argv[1], json.load(sys.stdin)
for grupo in sorted(chaves):
    if grupo == "professor": continue
    print(f"---- {grupo} ----")
    print(f"URL da API de IA: {url}")
    print(f"Chave do {grupo}: {chaves[grupo]}")
    print("No CloudShell: qc chave (cole a URL e a chave quando pedir)")
    print()
' "$(terraform output -raw url)"
```

Mande cada chave só ao seu grupo, por canal privado. As chaves aparecem na tela e ficam no histórico do terminal: não rode com a tela compartilhada.

### Acompanhar e revogar

Uso por grupo: **API Gateway → Usage plans → `qc-api-ia-...-turma` → Associated API keys → Usage**. O log da Lambda (`/aws/lambda/qc-api-ia-...`) traz o `api_key_id` de cada chamada; `terraform output chave_ids` diz de que grupo é cada id.

Revogar um grupo: tire o nome de `grupos` no `terraform.tfvars` e rode `terraform apply`. Trocar todas as chaves: `terraform apply -replace='aws_api_gateway_api_key.grupo["grupo-01"]'` (um por grupo) ou destroy e apply.

## Demo do Lab 5: o caminho direto com a sua conta

No Learner Lab, o caminho **Direto na AWS** do QC Cognitive Studio dá AccessDenied em Polly e Transcribe: a role `voclabs` não libera esses serviços. Para a demo do professor, o app usa credenciais da **sua conta pessoal**, a mesma da API, e os dois caminhos funcionam lado a lado.

**No CloudShell da conta pessoal** (confira o seu usuário no canto superior direito; não pode ser `voclabs`):

```bash
aws configure export-credentials --format process | python3 -c '
import json, sys
c = json.load(sys.stdin)
print("aws_access_key_id     :", c["AccessKeyId"])
print("aws_secret_access_key :", c["SecretAccessKey"])
print("aws_session_token     :", c["SessionToken"])
print("vence em              :", c.get("Expiration", "?"))
'
aws s3 ls | grep qc-api-ia          # DATA_BUCKET: o qc-api-ia-xxxxxx-temp
clear                               # depois de copiar
```

**Ou na sua máquina**, se a AWS CLI já estiver configurada com a conta pessoal (troque `pessoal` pelo nome do seu perfil, ou tire o `--profile` se for o padrão):

```powershell
aws configure export-credentials --profile pessoal --format powershell
aws s3 ls --profile pessoal | Select-String qc-api-ia
```

Com um usuário IAM de chave fixa, não há `aws_session_token`: deixe o campo vazio.

Na barra lateral do app:

| Campo | Valor |
|---|---|
| aws_access_key_id | `AccessKeyId` (começa com `ASIA` quando é temporária) |
| aws_secret_access_key | `SecretAccessKey` |
| aws_session_token | `SessionToken`, inteiro |
| Região | `us-east-1` |
| DATA_BUCKET | `qc-api-ia-xxxxxx-temp` (o Transcribe só lê áudio do S3) |

Teste antes da aula com **Comparar os dois** nas três abas.

> ⚠️ Essa credencial tem as permissões do seu usuário na conta pessoal. Gere sem a tela projetada, não grave em `.env`, `launch.json` nem `secrets.toml`, e não entregue aos alunos. A do CloudShell vence em cerca de 1 hora: gere de novo pouco antes da demo e repita se o app mostrar `ExpiredToken`. As chamadas diretas não passam pelo API Gateway, então a cota por grupo não vale para elas; quem segura o gasto é o budget.

## No fim de cada aula

As chaves foram mostradas aos grupos e circulam em CloudShells e notebooks. Não deixe a API no ar depois do encontro. Duas saídas:

```bash
# A) desligar tudo (a próxima turma faz um apply novo, com chaves novas)
terraform destroy

# B) manter a API e invalidar as chaves vistas em aula (uma linha por grupo)
terraform apply -replace='aws_api_gateway_api_key.grupo["grupo-01"]' -replace='aws_api_gateway_api_key.grupo["grupo-02"]'
```

Os alunos foram avisados de que a API só existe durante a aula: a transcrição e o sentimento são salvos no `evidencias-aula04.md`, e o exercício 2.1 tem um modo `simular` que dispensa a API.

## Depois da disciplina

```bash
terraform destroy
```

O AWS Budget sai junto. Os jobs do Transcribe são apagados pela própria função a cada transcrição.
