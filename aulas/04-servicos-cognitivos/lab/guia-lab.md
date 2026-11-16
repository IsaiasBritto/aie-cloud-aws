# Guia de Laboratório — Aula 4
## Serviços de IA da AWS & APIs

**Disciplina:** Cloud & Cognitive Environments
**MBA:** AI Engineering & Multi-Agents — FIAP
**Plataforma:** Amazon Web Services (AWS Academy Learner Lab)
**Ambiente:** **AWS CloudShell** — tudo no browser · região `us-east-1`

---

## Visão geral do lab

O agente da QC ganha sentidos: ouvir e falar, ler e ver. Cada sentido vem de um serviço de IA pronto, e cada um chega à Lambda por um de dois caminhos.

| Caminho | Serviços | Como a Lambda se autentica |
|---|---|---|
| Na própria conta | Rekognition (visão) e Textract (documentos) | Pela execution role (LabRole). Nenhuma chave |
| Por uma API de terceiro | Voz e sentimento (Polly, Transcribe e Comprehend), pela **API de IA da QC** que o professor hospeda | API key do grupo, guardada no **Secrets Manager**. A Lambda lê o segredo pela LabRole: também nenhuma chave no código |

> **Por que dois caminhos:** o Learner Lab não libera Polly, Transcribe nem Comprehend. Em vez de esconder a limitação, a aula usa o caso real: muitas tools de agente consomem APIs de terceiros (pagamento, frete, um LLM de outro provedor), e a pergunta "onde fica a chave?" aparece em todo projeto.

```
Abertura — limpeza da Aula 3, pré-voo, apply e qc.sh                     ~10 min
Lab 1    — reviews no DynamoDB                                           ~15 min  (Bloco 1)
Lab 2    — voz pela API de IA: a chave no Secrets Manager                ~25 min  (Bloco 2)
Lab 3    — sentimento das reviews (API de IA) e a etiqueta (Textract)    ~25 min  (Bloco 3)
Lab 4    — catálogo por chamada direta e moderação por evento do S3      ~25 min  (Bloco 4)
Demo     — QC Cognitive Studio (professor)                               ~10 min
Lab 5    — o mesmo app em cada grupo: API de IA × caminho direto         ~20 min  (Bloco 4)
Wrap-up  — terraform destroy + verificação de custo                       ~5 min
```

Cada passo segue o ritmo das aulas anteriores: **um comando `qc`, a verificação no console, uma pergunta para o grupo.** Os blocos de teoria acontecem entre os labs.

> **A API de IA só existe durante a aula.** No fim do encontro o professor desliga a API e as chaves dos grupos param de funcionar. Tudo o que depende dela (a transcrição do Lab 2 e o sentimento do Lab 3) tem que ser **salvo na hora**, no arquivo de evidências descrito abaixo. O resto da entrega roda depois da aula, pela LabRole.

### Evidências para a Entrega 04

Crie o arquivo no repositório do grupo logo no começo da aula e vá completando ao fim de cada lab:

```bash
mkdir -p ~/qc-grupo-NN/aula04 && touch ~/qc-grupo-NN/aula04/evidencias-aula04.md
```

| Lab | O que salvar | Precisa da API de IA? |
|---|---|---|
| Lab 2 | A transcrição do `bbc_trecho.mp3` (saída do `qc transcreve bbc_trecho.mp3`) | **Sim: só em aula** |
| Lab 3 | A saída do `qc tabela reviews` com o sentimento das 10 reviews | **Sim: só em aula** |
| Lab 3 | Os campos que o Textract leu da etiqueta (saída do `qc documento`) | Não |
| Lab 4 | O status de moderação das fotos testadas (`qc tabela reviews` depois do `qc foto-review`) | Não |

Cole a saída do terminal como texto, num bloco de código. Não cole links `ouvir` (eles carregam a credencial temporária da sessão) nem a chave do grupo.

> **Regra de ouro:** `terraform destroy` ao final. Rekognition, Textract e DynamoDB on-demand cobram por chamada; o segredo, US$ 0,40 por mês proporcional enquanto existir.

---

## Abertura — limpeza da Aula 3, pré-voo e apply (10 min)

**A Aula 3 foi destruída?** Tag Editor (região `us-east-1`, *All supported resource types*, tag `aula = 3`). Cluster, serviço e task definition do ECS aparecem como INACTIVE e não cobram. Se sobrou algo ativo: `cd ~/aie-cloud/aulas/03-serverless-containers/lab/terraform && terraform destroy -auto-approve`.

```bash
# Ainda não clonou? Clone:
cd ~ && git clone https://github.com/IsaiasBritto/aie-cloud-aws.git aie-cloud

# Já clonou? Atualize SEM apagar a pasta (apagar leva junto o terraform.tfstate das aulas anteriores):
git -C ~/aie-cloud stash && git -C ~/aie-cloud pull

cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab

# Pré-voo: a sessão chega a S3, Lambda, DynamoDB, Secrets Manager, Rekognition e Textract?
bash check_servicos.sh

# Terraform no $HOME (se ainda não instalou) e o apply
bash ~/aie-cloud/aulas/01-fundamentos-iac/lab/install_terraform.sh
export PATH="$HOME/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

cd terraform
terraform init
terraform apply -auto-approve      # ~1 min

# O comando qc (carregue de novo a cada sessão nova do CloudShell)
source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/qc.sh
qc publica                         # empacota a Lambda com as dependências e publica
```

---

## Lab 1 — Reviews no DynamoDB (Bloco 1)

### Passo 1 — O que o Terraform criou

Enquanto o `apply` roda, leia os arquivos:

| Arquivo | O que define |
|---------|--------------|
| [main.tf](terraform/main.tf) | Providers, tags, locals, data source da LabRole |
| [storage.tf](terraform/storage.tf) | Bucket de dados (prefixos `audios/`, `documentos/`, `imagens/`, `reviews-fotos/`) e o **evento** que liga `reviews-fotos/` à Lambda |
| [lambda.tf](terraform/lambda.tf) | Lambda Python 3.12 + Function URL + LabRole (timeout 60 s) |
| [dynamodb.tf](terraform/dynamodb.tf) | Tabelas on-demand `reviews` (partição `produto`, ordenação `id`) e `produtos` (o catálogo) |
| [secrets.tf](terraform/secrets.tf) | O segredo da API de IA, **vazio**: o valor entra no Lab 2 |
| [outputs.tf](terraform/outputs.tf) | Os nomes que o `qc.sh` exporta |

Nada no Terraform cria "um Rekognition" ou "um Textract": são APIs da conta, liberadas por IAM.

### Passo 2 — Semear as reviews

```bash
qc semeia
qc tabela reviews
```

Console: **DynamoDB** → Tables → `qc-aula04-xxxxxx-reviews` → **Explore table items**.

> **Para discutir:** procure no [`semear_reviews.py`](scripts/semear_reviews.py) uma senha, um host, uma porta, uma chave. Não há. Quem autoriza a gravação?

### Passo 3 — A primeira API pronta

Até aqui o lab preparou a base e colocou o problema na mesa: reviews que ninguém leu. Antes de seguir, uma chamada a uma API pronta, com a mesma foto do slide "a mesma foto, três respostas":

```bash
qc rotulos
```

Uma chamada só, sem treinar nada e sem criar recurso: o Tag Editor continua sem nenhum "Rekognition". Custa cerca de US$ 0,001 por imagem.

> **Para discutir:** o Rekognition sabe que é um teclado. Ele sabe qual modelo é da QC? E consegue escrever uma descrição para o cliente? A primeira pergunta é de modelo custom; a segunda, de LLM. É a decisão do Bloco 1 na prática.

**✅ Checkpoint L₁:** 10 reviews na tabela, ainda sem coluna de sentimento, e os rótulos do produto na tela.

---

## Lab 2 — Voz pela API de IA da QC (Bloco 2)

### Passo 1 — A chave do grupo vai para o cofre

O professor entrega a cada grupo a **URL** da API de IA e uma **chave** (fora do repositório, fora do chat da turma). Antes de gravar, veja o que acontece sem ela:

```bash
qc fala "teste"         # → 503: "o segredo da API de IA ainda está vazio: rode qc chave"
qc chave                # cole a URL e a chave; a chave não aparece na tela
qc status               # Segredo: ... (chave gravada: sim)
```

Console: **Secrets Manager** → `qc-aula04-xxxxxx/api-ia` → **Retrieve secret value**.

O `qc chave` grava direto no Secrets Manager. A chave não passa pelo código, pelo Terraform, pelo `terraform.tfstate` nem pelo histórico do shell. A Lambda só conhece o **nome** do segredo (variável `SECRET_NAME`) e lê o valor pela LabRole.

### Passo 2 — Texto → fala

```bash
qc fala "Olá! Aqui é a assistente da Quantum Commerce. Seu pedido saiu para entrega."
qc fala "Seu pedido chega amanhã." Thiago       # outra voz
```

Abra o link `ouvir` no navegador (vale 1 hora). O caminho: a Lambda lê o segredo, chama `POST /tts` da API de IA com o cabeçalho `x-api-key`, recebe o MP3 em base64 e grava em `audios/` no seu bucket.

### Passo 3 — Fala → texto

```bash
qc transcreve                      # transcreve a última fala do Polly
qc transcreve bbc_trecho.mp3       # 40 s de fala real (BBC News Brasil)
```

A transcrição leva de 10 a 25 s: o Transcribe trabalha com **job assíncrono**, e a API espera o job terminar.

> **Conexão com a Aula 3 — "na Lambda, você paga a espera":** enquanto o Transcribe trabalha, a sua Lambda fica parada esperando a resposta, e paga por esse tempo. Em produção, o job seria iniciado e o resultado chegaria por evento.

### Passo 4 — Ver o código

Abra [function_app.py](function/function_app.py) e ache `_credencial_api()` e `_api_ia()`. Repare no cache de 5 minutos do segredo e no que a função faz quando recebe 403.

> **Para discutir:** se a chave do grupo vazar num `git push`, quem consegue usá-la? O que o professor faz para cortar só o seu grupo? O que limita o estrago enquanto isso? (Dica: usage plan, cota diária e limite de concorrência da API.)

**✅ Checkpoint L₂:** o link toca o áudio e a transcrição volta em português.

> **Salve agora no `evidencias-aula04.md`:** a transcrição do `bbc_trecho.mp3`. Depois da aula a API de IA sai do ar e não dá para gerar de novo.

---

## Lab 3 — Ler: sentimento e documento (Bloco 3)

### Passo 1 — Sentimento das reviews

```bash
qc reviews                # as 10 reviews numa chamada só (o batch do Comprehend, pela API de IA)
qc tabela reviews         # o sentimento gravado ao lado das estrelas
qc reviews                # de novo: "Nenhuma review nova" — o filtro evita pagar duas vezes
```

A rota lê do DynamoDB as reviews **sem** o atributo `sentimento` (`attribute_not_exists(sentimento)`), manda os textos para `POST /sentimento` e grava sentimento, scores e entidades de volta em cada item.

> **Lembra do Query × Scan da Aula 2?** Para achar as pendentes, a rota faz um **Scan** com filtro: lê a tabela inteira. Com 10 reviews, tudo bem. Com 10 milhões, cada chamada paga a tabela toda. Em produção: um gatilho do **DynamoDB Streams** analisa cada review no momento em que ela é gravada.

### Passo 2 — A etiqueta de envio (Textract)

```bash
qc documento              # data/etiqueta.png: uma etiqueta fictícia da QC
```

A mesma imagem passa por duas chamadas do Textract, pela LabRole:

| Chamada | Devolve | Custo por página |
|---|---|---|
| `detect_document_text` | linhas soltas, sem saber o que é o quê | US$ 0,0015 |
| `analyze_document` com `FORMS` | pares **campo → valor** ("Pedido" → "QC-48213"), com confiança | US$ 0,05 |

> **Para discutir:** o FORMS custa 33 vezes mais. Quando o OCR puro basta? E repare na limitação: o Textract entende formulários em português, mas as *Queries* ("qual o CEP?") e a leitura de notas e recibos são só em inglês. É um dos motivos para um LLM entrar na Aula 5.

**✅ Checkpoint L₃:** a distribuição de sentimentos bate com as estrelas? O Textract achou pedido, CEP e valor declarado?

> **Salve agora no `evidencias-aula04.md`:** a saída do `qc tabela reviews` com o sentimento das 10 reviews (só em aula) e a saída do `qc documento`. O exercício 2.1 e o bônus 3.1 usam esse sentimento.

---

## Lab 4 — Ver: catálogo e moderação (Bloco 4)

### Passo 1 — Catálogo automático (chamada direta)

```bash
qc catalogo                       # data/produto.jpg
qc tabela produtos
```

O Rekognition devolve rótulos e o texto da imagem, e a Lambda grava como tags do produto na tabela `produtos`. Você chamou a função e esperou a resposta.

### Passo 2 — Moderação da foto da review (evento)

Um cliente anexa uma foto à review `r002`:

```bash
qc foto-review r002 review-foto-praia.jpg
qc foto-review r004 produto.jpg
qc tabela reviews
```

Desta vez **ninguém espera a função**. Numa conta AWS normal, o upload em `reviews-fotos/` já dispara a Lambda: o evento está configurado no [storage.tf](terraform/storage.tf). A função roda `detect_moderation_labels` e marca a review como `publicada` ou `em_revisao`, e o resultado aparece na tabela e no log, não na tela.

> **No Learner Lab, o S3 não entrega o evento.** Testamos a notificação direta do S3 e a rota pelo EventBridge: as duas ficam configuradas sem erro, mas a função nunca é acionada. Por isso o `qc foto-review` faz o papel do S3: depois de copiar a foto, ele entrega à função o mesmo evento que o S3 mandaria, de forma **assíncrona** (`aws lambda invoke --invocation-type Event`). A resposta é um HTTP 202 sem conteúdo: o pedido entrou na fila, e ninguém espera o resultado. O código da função é exatamente o de produção.

```bash
aws logs tail /aws/lambda/$FUNC_NAME --since 10m --format short | grep moderação
```

> **Para discutir:** a foto da praia foi para revisão por *Swimwear or Underwear*. Numa loja de moda praia, isso é um falso positivo que trava o negócio. Onde mora essa regra: no Rekognition ou no seu código? (Procure `BLOQUEIA` no [function_app.py](function/function_app.py).)

**✅ Checkpoint L₄:** `r002` em revisão, `r004` publicada, e o teclado no catálogo com as tags.

---

## Demo — QC Cognitive Studio (professor, ~10 min)

O professor roda o app [Streamlit](app/README.md) na própria máquina (o navegador só libera o microfone em `localhost` ou HTTPS) e compara dois caminhos para a mesma operação: pela API de IA, com a chave do lado do servidor, e direto na AWS, com uma access key no app. O resultado é o mesmo; o risco, não.

**A pergunta que fecha a aula:** se o caminho direto é mais rápido e mais simples, por que a arquitetura da disciplina insiste no outro?

---

## Lab 5 — Front-end: QC Cognitive Studio (Bloco 4, ~20 min)

**Objetivo:** sair do terminal e usar os serviços numa interface e, no caminho, comparar **duas arquiteturas de acesso à IA** que produzem o mesmo resultado com riscos bem diferentes. É o mesmo app da demo do professor; agora cada grupo roda o seu.

Todo o Lab 5 roda na **sua máquina**, no VS Code. Não é no CloudShell: o navegador só libera o microfone em `localhost`. O CloudShell entra só no Passo 0, para buscar os valores que o app pede.

**Antes de começar, no notebook:** Python 3.11 ou 3.12, Git e o VS Code com a extensão **Python** (Microsoft).

### Passo 0 — Coletar os valores do app (no CloudShell)

```bash
source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/qc.sh
qc app
```

O `qc app` junta numa tela tudo o que a barra lateral do app pede:

| Campo no app | De onde vem | Usado em |
|---|---|---|
| URL da API de IA | o segredo do grupo (o que o `qc chave` gravou) | Via API de IA |
| API key | o segredo do grupo | Via API de IA |
| aws_access_key_id | a credencial da sessão do CloudShell | Caminho direto |
| aws_secret_access_key | idem | Caminho direto |
| aws_session_token | idem | Caminho direto |
| Região | `us-east-1` | Caminho direto |
| DATA_BUCKET | o bucket do grupo | Caminho direto, só a transcrição |

Copie os valores para um bloco de notas **local** (não para o repositório) e rode `clear`. A credencial do CloudShell vence antes da sessão do Learner Lab, e o `qc app` mostra a hora; se o app começar a dar `ExpiredToken`, rode `qc app` de novo ou use **AWS Details** → **AWS CLI: Show** no Learner Lab, que vale a sessão inteira.

> Os valores são sensíveis: não projete, não cole no chat da turma, não grave em `.env` nem no `launch.json`.

### Passo 1 — Clonar e abrir o repositório no VS Code

No terminal do VS Code (**Terminal → New Terminal**):

```bash
git clone https://github.com/IsaiasBritto/aie-cloud-aws.git
cd aie-cloud-aws
code .
```

Se você já tem o clone, basta um `git pull` para trazer o Lab 5.

### Passo 2 — Criar o ambiente virtual do app

Ainda no terminal integrado, a partir da raiz do repositório.

**Windows (PowerShell):**

```powershell
cd aulas\04-servicos-cognitivos\lab\app
py -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Se o PowerShell bloquear o `Activate.ps1`, rode antes `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

**macOS ou Linux:**

```bash
cd aulas/04-servicos-cognitivos/lab/app
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Depois, aponte o VS Code para esse ambiente: `Ctrl+Shift+P` (no Mac, `Cmd+Shift+P`) → **Python: Select Interpreter** → o `.venv` que está em `lab/app`. O `.venv` não vai para o Git.

### Passo 3 — Rodar o app

Com o `.venv` ativo:

```bash
streamlit run app.py
```

O navegador abre em `http://localhost:8501`. Use exatamente esse endereço: o microfone da aba "Fala → Texto" só funciona em `localhost`.

**Opcional — rodar e depurar com F5.** Crie `.vscode/launch.json` na raiz do repositório:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Lab 5 · QC Cognitive Studio",
      "type": "debugpy",
      "request": "launch",
      "module": "streamlit",
      "args": ["run", "app.py", "--server.headless", "false"],
      "cwd": "${workspaceFolder}/aulas/04-servicos-cognitivos/lab/app",
      "justMyCode": true
    }
  ]
}
```

Com breakpoints em `tts_lambda`, `stt_lambda` ou `visao_direto`, você vê o que vai e o que volta em cada caminho, inclusive a requisição saindo com o cabeçalho `x-api-key`.

### Passo 4 — Primeiro só a API de IA

Na barra lateral, preencha **só** a URL da API de IA e a API key do Passo 0. Deixe as credenciais da AWS em branco, escolha **Via API de IA** e use as três primeiras abas.

| Aba | O que fazer |
|---|---|
| 🔊 Texto → Fala | Sintetize uma frase e baixe o WAV: ele serve de entrada para a aba seguinte |
| 🎤 Fala → Texto | Grave do microfone ou envie o WAV baixado |
| 🖼️ Visão + Espacial | Envie `data/produto.jpg` ou uma foto sua: tags, texto e caixas desenhadas sobre a imagem |
| 🏛️ Arquitetura | A comparação e as perguntas de discussão |

Tudo funciona, e o app não tem credencial nenhuma da AWS. Essa é a demonstração.

> **Se a transcrição vier vazia com 200:** teste com o WAV baixado da aba de fala. Se esse funcionar, o problema é o áudio do microfone, não o serviço. Separar "formato errado" de "serviço fora" é metade do exercício.

### Passo 5 — Agora o caminho direto

Preencha as três credenciais, a **Região** (`us-east-1`) e o **DATA_BUCKET** com os valores do Passo 0. O DATA_BUCKET é necessário porque o Transcribe só lê áudio do S3: sem ele, a aba de transcrição para antes de chegar no serviço. Escolha **Comparar os dois** e rode as três abas.

- **Visão:** funciona pelos dois caminhos. Compare os tempos: o direto é mais rápido, com um salto a menos.
- **Fala e transcrição:** o caminho direto devolve **AccessDenied**. A credencial da sessão não tem Polly nem Transcribe; a API de IA tem.

### Passo 6 — Discutir (em grupo)

1. Se o direto é mais rápido e mais simples, por que a arquitetura da disciplina insiste numa API na frente?
2. Este app roda no seu notebook. Se virasse uma página web pública, o que aconteceria com o session token dentro do JavaScript entregue ao navegador?
3. O que a chave do grupo abre? E o session token que você acabou de colar?
4. Um colega commita o app no GitHub com o token preenchido. Apagar o arquivo e commitar de novo resolve?

**✅ Checkpoint L₅:** as três abas funcionam com as credenciais da AWS em branco, e o grupo sabe explicar por que a fala falha no caminho direto.

> Ao terminar, apague as credenciais da barra lateral ou feche a aba: o app não guarda nada em disco, e o session token do Learner Lab vale até a sessão acabar.

---

## Wrap-up — Destroy e custo zero (5 min)

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab/terraform
terraform destroy -auto-approve
```

O destroy apaga a Lambda, o bucket (com áudios, imagens e documentos), as duas tabelas e o **segredo, na hora** (`recovery_window_in_days = 0`; o padrão deixaria o segredo agendado por 7 dias, cobrando).

**Conferir:** Tag Editor com a tag `aula = 4` → a busca deve voltar **vazia**; e o crédito consumido na página do Learner Lab.

---

## Conexão com o projeto Quantum Commerce

A Lambda da QC agora tem **tools cognitivas**:

```
POST /falar                       ← Polly, pela API de IA (o agente responde por voz)
POST /transcrever?arquivo=        ← Transcribe, pela API de IA (atendimento por voz)
POST /analisar-reviews            ← Comprehend, pela API de IA (sentimento das reviews)
POST /ler-documento?arquivo=      ← Textract (etiquetas e formulários)
POST /analisar-imagem?arquivo=    ← Rekognition (catálogo a partir da foto)
evento reviews-fotos/             ← Rekognition (moderação, sem ninguém esperar)
```

Somadas à tool de catálogo da Aula 3 (`GET /produtos`), o agente busca produtos, ouve e responde o cliente, entende o sentimento das reviews, lê etiquetas e reconhece produtos por foto. Na Aula 5, o Bedrock decide qual tool usar em cada conversa.

---

## Troubleshooting

| Problema | Causa | Solução |
|----------|-------|---------|
| `{"status": "placeholder"}` em qualquer rota | O código real ainda não foi publicado | `qc publica` |
| `Runtime.ImportModuleError: No module named 'aws_lambda_powertools'` | O zip foi feito sem as dependências | `qc publica` (ele instala as dependências no pacote) |
| `503` "o segredo da API de IA ainda está vazio" | Faltou o Passo 1 do Lab 2 | `qc chave` |
| `502` "API de IA respondeu 403" | Chave ou URL errada, ou chave revogada | `qc chave` de novo, com a URL e a chave que o professor entregou |
| `502` "API de IA respondeu 429" | A cota diária do grupo acabou | Avise o professor |
| `qc transcreve` → `IN_PROGRESS` | Áudio longo para uma chamada síncrona | Use um trecho mais curto (até ~1 min) |
| `qc foto-review` → "a review não existe" | As reviews não foram semeadas nesta tabela | `qc semeia` e `qc tabela reviews` |
| `qc foto-review` → "Sem resultado na tabela em 30 s" | A função falhou ao moderar | O log: `aws logs tail /aws/lambda/$FUNC_NAME --since 5m` |
| `AccessDenied ... GetBucketObjectLockConfiguration` no `apply` | O Learner Lab bloqueia essa leitura do `aws_s3_bucket` | `git -C ~/aie-cloud pull` e `terraform apply`: o lab cria o bucket pelo módulo `modulos/bucket-s3` |
| `403 Forbidden` na Function URL | Falta uma das duas permissões da URL pública | `terraform apply` de novo; `aws lambda get-policy --function-name "$FUNC_NAME"` |
| `ERRO: FUNC_URL vazio` | Sessão nova do CloudShell | `source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/qc.sh` |
| `check_servicos.sh` com ✗ ou `voc-cancel-cred` | Sessão do Learner Lab expirou | **Start Lab** e CloudShell novo |
| `No space left on device` | O `$HOME` do CloudShell tem 1 GB | `du -sh ~/* ~/.??* \| sort -h`; apague `~/.cache` e pacotes antigos. O `qc publica` já monta o pacote em `/tmp` |

---

## Tarefa pós-aula

1. Conferir o `evidencias-aula04.md` montado em aula. O que depende da API de IA (transcrição e sentimento) não pode ser refeito depois; o Textract e a moderação podem, num Learner Lab novo, com `terraform apply` e os comandos do lab.
2. Levar para o `entrega-grupo-aula04.md` a distribuição de sentimentos das 10 reviews comparada com as estrelas.
3. Resolver pelo menos N1 + N2 dos exercícios. O 2.1 não precisa da API de IA: veja o modo `simular` no enunciado.

---

## Referências

- [Amazon Rekognition — moderação de conteúdo](https://docs.aws.amazon.com/rekognition/latest/dg/moderation.html)
- [Amazon Textract — formulários (key-value)](https://docs.aws.amazon.com/textract/latest/dg/how-it-works-kvp.html)
- [AWS Secrets Manager — boas práticas](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [Amazon S3 — notificações de evento para a Lambda](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
- [API Gateway — usage plans e API keys](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-usage-plans.html)
- [Powertools for AWS Lambda (Python) — Event Handler](https://docs.powertools.aws.dev/lambda/python/latest/core/event_handler/api_gateway/)
