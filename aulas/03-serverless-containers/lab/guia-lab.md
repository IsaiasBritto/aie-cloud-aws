# Guia de Laboratório — Aula 3

**Tema:** Serverless & Containers
**Plataforma:** Amazon Web Services (AWS Academy Learner Lab)
**Ambiente:** **AWS CloudShell** — tudo no browser, sem instalar nada
**Região:** `us-east-1`

---

## Visão geral do lab

A aula gira em torno de uma ferramenta só: a pergunta 1 da Aula 2 ("tem cadeira boa pra coluna até R$ 1.500?") vira `buscar_produtos(categoria, preco_max)`, que um agente chama por HTTP. Ela mora primeiro numa Lambda e depois num container; no Bloco 4 a turma decide qual casa serve para cada carga da QC.

```
Abertura    — limpeza da Aula 2, terraform apply e o qc.sh              ~15 min
Atividade 1 — publicar e chamar a ferramenta v1 (mock)               ~20 min  (Bloco 1)
Atividade 2 — v2 lê o S3 pela role + o filtro preco_max              ~20 min  (Bloco 2)
Atividade 3 — a mesma ferramenta num container: ECR e Fargate        ~35 min  (Bloco 3)
Wrap-up     — terraform destroy + verificação de custo               ~5 min   (Bloco 4)
```

Cada passo segue o mesmo ritmo da Aula 2: **um comando `qc`, a verificação no console, uma pergunta para o grupo.** Os tempos casam com o roteiro do deck (slide 2); os blocos de teoria acontecem entre as atividades.

> **Regra de ouro:** sempre encerrar com `terraform destroy`.

---

## Pré-requisitos

- ✅ Aula 1 concluída (Learner Lab, CloudShell, Terraform no `$HOME`)

> **Aula independente:** esta aula **não depende da Aula 2**. O Terraform cria o próprio bucket e já sobe o `produtos.csv` no `apply` (de [lab/data/produtos.csv](data/produtos.csv)).

---

## Abertura — limpeza da Aula 2 e preparação (10 min)

**A Aula 2 foi destruída?** RDS esquecido ligado é o recurso que mais consome crédito. No console: **Resource Groups & Tag Editor → Tag Editor** → região `us-east-1`, *All supported resource types*, tag `aula = 2` → a busca deve voltar **vazia**. Se sobrou algo:

```bash
source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh   # recupera a DB_PASSWORD
cd ~/aie-cloud/aulas/02-storage-bancos/lab/terraform
terraform destroy -auto-approve -var="db_password=$DB_PASSWORD"
```

**Preparação:**

```bash
# Ainda não clonou? Clone:
cd ~ && git clone https://github.com/IsaiasBritto/aie-cloud-aws.git aie-cloud

# Já clonou? Atualize SEM apagar a pasta (apagar leva junto o terraform.tfstate das aulas anteriores):
git -C ~/aie-cloud stash && git -C ~/aie-cloud pull

cd ~/aie-cloud/aulas/03-serverless-containers/lab/terraform

# Terraform no $HOME (só se ainda não instalou)
bash ~/aie-cloud/aulas/01-fundamentos-iac/lab/install_terraform.sh
export PATH="$HOME/bin:$PATH"
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Ferramentas
aws sts get-caller-identity --query Arn --output text
terraform -version
docker --version

terraform init
terraform apply -auto-approve      # ecs_enabled=false (padrão) → o serviço no Fargate só nasce na Atividade 3
```

Depois do `apply`, prepare a sessão:

```bash
source ~/aie-cloud/aulas/03-serverless-containers/lab/qc.sh
qc            # mostra os comandos do lab
```

O [`qc.sh`](qc.sh) lê os outputs do Terraform (bucket, função, Function URL, ECR, cluster) e cria o comando `qc`. A sessão do CloudShell caiu (ela encerra depois de ~20 min sem uso)? Rode o mesmo `source`: o estado do Terraform fica no `$HOME`.

---

## Atividade 1 — Lambda HTTP via Terraform + deploy (L₁)

### Passo 1 — O que o Terraform criou

Enquanto o `apply` da abertura trabalha (~2 a 4 min), leia os arquivos:

| Arquivo | O que define |
|---------|--------------|
| [main.tf](terraform/main.tf) | Providers, sufixo aleatório, tags padrão, locals, LabRole |
| [variables.tf](terraform/variables.tf) | `region` e `ecs_enabled` (para criar o ECS depois) |
| [outputs.tf](terraform/outputs.tf) | Nomes e endpoints consumidos pelos comandos |
| [storage.tf](terraform/storage.tf) | Bucket S3 pelo módulo [`modulos/bucket-s3`](../../../modulos/bucket-s3/main.tf) (prefixo `catalogo/`) + upload do `produtos.csv` |
| [lambda.tf](terraform/lambda.tf) | Lambda Python 3.12 + Function URL + LabRole como execution role |
| [containers.tf](terraform/containers.tf) | ECR + cluster ECS + tarefa Fargate (count condicional) |

### Passo 2 — Deploy da versão mock (v1)

Antes, abra o [`lambda_function.py`](function/v1-mock/lambda_function.py) da v1-mock: é Python puro, sem framework. O `lambda_handler` recebe o **evento HTTP** da Function URL e escolhe a rota olhando o `rawPath` (`/health`, `/produtos`); os filtros vêm de `queryStringParameters`. Isso é tudo o que uma Lambda precisa saber de HTTP.

```bash
qc publica v1
```

Por baixo, o `qc publica` empacota a pasta `function/v1-mock` num zip (de dentro da pasta, para o `lambda_function.py` ficar na raiz), envia com `aws lambda update-function-code` e espera a função terminar de atualizar (`aws lambda wait function-updated`).

### Passo 3 — Chamar a ferramenta

```bash
qc chama /produtos
qc chama "/produtos?categoria=eletronicos"
qc chama /health
```

O `qc chama` faz a requisição HTTPS na Function URL, mostra o JSON, o código HTTP, o tempo e a URL.

> ⚠️ **Esperado, não é falha:** a primeira chamada leva ~1 s (cold start). As seguintes são milissegundos.

**No console:** abra a Function URL no navegador e no celular. Depois, **CloudWatch** → **Log groups** → `/aws/lambda/qc-aula03-…-catalogo` → o stream mais recente: a primeira chamada tem a linha `REPORT` com **Init Duration** (o cold start); as seguintes, não.

**Pergunta para o grupo:** quanto custaria se o agente chamasse esta ferramenta 100 mil vezes por dia? (A conta está no deck, logo depois do lab.)

**✅ Checkpoint L₁:** o `qc chama` devolve o JSON com os 5 produtos do mock?

---

## Atividade 2 — Lambda lendo o S3 com a execution role (L₂)

### Conferir o que já foi provisionado

- **S3** → bucket `qc-aula03-xxxxxx-catalogo` → `catalogo/produtos.csv` (subiu no apply)
- **Lambda** → a função → **Configuration** → **Environment variables**: `BUCKET_NAME` e `CSV_KEY`
- **Configuration** → **Permissions**: a execution role é a **LabRole**

### Passo 1 — Publicar a v2-s3

```bash
qc publica v2
qc chama /health                      # "source": "s3"
qc chama "/produtos?categoria=moveis" # agora com estoque e descrição: vem do CSV no S3
```

> **Plano B:** se vier `AccessDenied` ou `NoSuchKey`, confira a variável `BUCKET_NAME` da função e se o `produtos.csv` está em `catalogo/` (`aws s3 ls "s3://$BUCKET_NAME/catalogo/"`).

### Passo 2 — A permissão no console

**Lambda** → a função → **Configuration** → **Permissions**: a execution role é a **LabRole**. Clique nela e veja as policies: ela pode muito mais que ler o `catalogo/`.

**Pergunta para o grupo:** se essa role vazasse, o que o atacante levaria? Qual seria a policy mínima da ferramenta? *(`s3:GetObject` só em `arn:aws:s3:::<bucket>/catalogo/*`. No Learner Lab não dá para criar roles: fica como exercício escrito, o 1.2 da entrega.)*

### Passo 3 — Reflexão (3 min)

Anote no `entrega-grupo-aula03.md`:

1. Procure "key", "password", "credential", "secret" em todo o código da v2-s3. O que você encontra?
2. Como a Lambda consegue ler o S3 "sem credenciais"? *(a execution role vira credencial temporária em variáveis de ambiente do runtime, renovada pela própria Lambda)*
3. Se um agente em produção precisasse acessar 5 buckets diferentes, qual seria a estratégia? *(uma role por função, com política restrita aos ARNs dos 5 buckets)*

### Passo 4 — Exercício: o filtro `preco_max` (8 min)

O cliente perguntou "tem cadeira boa pra coluna até R$ 1.500?". A ferramenta já entende `categoria=moveis`; falta o preço máximo. Adicione o filtro `preco_max` na v2-s3:

1. `nano ~/aie-cloud/aulas/03-serverless-containers/lab/function/v2-s3/lambda_function.py`
2. Em `listar_produtos`, no comentário `# Lab 2: o filtro preco_max entra aqui`, filtre `resultado` pelos produtos com `preco` menor ou igual a `preco_max` (o valor chega como texto na query string)
3. Salve (**Ctrl+X → Y → Enter**), publique e faça a pergunta do cliente:

```bash
qc publica v2
qc chama "/produtos?categoria=moveis&preco_max=1500"
# Esperado: 3 cadeiras (DXRacer R$ 1.499,90, Gamer R$ 1.299,00, Home Office R$ 799,00); a mesa de R$ 2.899 sai
```

<details>
<summary>Gabarito</summary>

```python
    preco_max = params.get("preco_max")
    if preco_max:
        resultado = [p for p in resultado if p["preco"] <= float(preco_max)]
    return resposta({"total": len(resultado), "produtos": resultado})
```

Se o `float()` receber algo que não é número (`?preco_max=abc`), a função quebra com erro 500. Bom gancho para discutir validação de entrada numa tool de agente: o modelo pode mandar qualquer coisa.
</details>

O `preco_max` vira um parâmetro novo da tool (ver [Conexão com o projeto](#conexão-com-o-projeto-quantum-commerce)).

Repare: a ferramenta devolve as 3 cadeiras, mas não sabe qual é "boa pra coluna". Essa é a busca pelo sentido da Aula 2; o agente junta as duas.

**✅ Checkpoint L₂:** a função retorna os produtos reais do CSV, e `categoria=moveis&preco_max=1500` traz só as 3 cadeiras?

---

## Atividade 3 — Container: build no CloudShell, ECR e ECS Fargate (L₃)

### Conferir o código FastAPI

[docker/app.py](docker/app.py) tem a mesma lógica da v2-s3, em FastAPI, **já com o `preco_max`**: é a mesma ferramenta. Compare o roteamento: na Lambda, um `if` no `rawPath`; aqui, o **decorator** `@app.get("/produtos")`, e o FastAPI converte a query string nos parâmetros da função. O [Dockerfile](docker/Dockerfile) é multi-stage, com base do ECR Public e usuário não-root. Se alguém mandar `preco_max=abc`, o FastAPI devolve 422 (entrada inválida); a Lambda do gabarito quebraria com 500. Bom gancho: uma ferramenta de agente precisa validar o que recebe.

### Passo 1 — Build, ECR e a tarefa no Fargate

```bash
qc container
```

Por baixo, o `qc container` faz quatro coisas, na ordem:

```bash
cd ~/aie-cloud/aulas/03-serverless-containers/lab/docker
docker build --platform linux/amd64 -t "$ECR_URL:v1" .
aws ecr get-login-password | docker login --username AWS --password-stdin "${ECR_URL%%/*}"   # sem senha: a credencial da sessão
docker push "$ECR_URL:v1"
terraform -chdir=../terraform apply -auto-approve -var="ecs_enabled=true"   # cria o serviço com 1 tarefa e IP público
```

Depois espera a tarefa ficar RUNNING (até 5 min) e mostra a URL do container.

**No console:** **ECR** → `produtos-api` → a imagem `v1`, o tamanho e o resultado do scan. **ECS** → Clusters → `qc-aula03-xxxxxx-cluster` → Services → `produtos-api` → Tasks → **Logs**.

### Passo 2 — A mesma pergunta nas duas casas

```bash
qc compara "/produtos?categoria=moveis&preco_max=1500"
```

O `qc compara` faz a mesma chamada na Lambda e no container e mostra, lado a lado, o código HTTP, o tempo, quantos produtos voltaram e a URL de cada um. Rode duas ou três vezes e compare os tempos.

> Se as respostas forem diferentes, o filtro `preco_max` da Atividade 2 não está na v2 publicada: o container já vem com ele.

### Passo 3 — Comparação Lambda × ECS Fargate (5 min)

Preencha com o que vocês viram no `qc compara` e no console:

| Aspecto | Lambda | ECS Fargate |
|---------|--------|-------------|
| URL | `https://<id>.lambda-url.us-east-1.on.aws/produtos` | `http://<ip-da-tarefa>:8080/produtos` |
| TLS | ✅ Embutido | ❌ Precisa de ALB (ou ECS Express Mode, que já cria o ALB com HTTPS) |
| Cold start | ~1 s | Não há (sempre ligada) |
| Custo parado | US$ 0 | Paga por segundo enquanto a tarefa existir |
| Auto-scale | ✅ Automático | Configurável (Service Auto Scaling) |
| Duração máxima | 15 min por execução | Sem limite |
| Identidade | Execution role | Task role |

**Pergunta para o `entrega-grupo-aula03.md`:** para a QC, qual você levaria para produção da API de catálogo? Justifique em 3-5 frases (tráfego, custo, latência aceitável, complexidade operacional).

**✅ Checkpoint L₃:** o mesmo código respondeu `/produtos` como Lambda e como tarefa Fargate?

---

## Wrap-up — Destroy e custo zero (10 min)

```bash
cd ~/aie-cloud/aulas/03-serverless-containers/lab/terraform
terraform destroy -auto-approve -var="ecs_enabled=true"
```

Apaga Lambda, bucket, ECR (com as imagens) e o cluster ECS de uma vez. Depois confira o crédito consumido na página do Learner Lab — perto de zero.

> **Parar não é zerar:** tarefa parada, ECR ocioso — ainda há imagem armazenada e logs consumindo. Pausar não basta.

**Conferir:** Tag Editor com a tag `aula = 3` → a busca deve voltar **vazia**.

---

## Conexão com o projeto Quantum Commerce

A Function URL que você subiu é o endpoint de catálogo da QC — a **primeira tool** que os agentes vão consumir:

```json
{
  "name": "buscar_produtos",
  "description": "Busca produtos da Quantum Commerce por categoria e preço máximo",
  "url": "https://<id>.lambda-url.us-east-1.on.aws/produtos",
  "input_schema": {
    "type": "object",
    "properties": {
      "categoria": {"type": "string", "description": "Categoria (ex: moveis, eletronicos)"},
      "nome":      {"type": "string", "description": "Trecho do nome do produto"},
      "preco_max": {"type": "number", "description": "Preço máximo em reais (o filtro da Atividade 2)"}
    }
  }
}
```

Duas implementações: a Lambda, que vai para produção, e o container no ECR, como alternativa (ECS Fargate ou ECS Express Mode).

> **Sobre o App Runner:** a AWS fechou o App Runner para novos clientes e recomenda o **ECS Express Mode** no lugar: a partir da imagem no ECR, uma chamada cria serviço Fargate, Application Load Balancer com HTTPS e auto scaling. Ao contrário da Lambda, não escala a zero.

---

## Troubleshooting — Problemas comuns

| Problema | Causa | Solução |
|----------|-------|---------|
| `AccessDenied ... GetBucketObjectLockConfiguration` no `terraform apply` | O Learner Lab bloqueia essa leitura, que o `aws_s3_bucket` faz sempre. Os labs agora criam o bucket pelo módulo `modulos/bucket-s3` (AWS CLI) | `git -C ~/aie-cloud pull`, `terraform init`, `terraform state rm aws_s3_bucket.catalogo` e `terraform apply` de novo. O módulo reaproveita o bucket que já foi criado |
| `curl` na Function URL → `403 Forbidden` | Falta uma das duas permissões da URL pública | `terraform apply` de novo; confira com `aws lambda get-policy --function-name "$FUNCTION_NAME"` (precisa de `InvokeFunctionUrl` **e** `InvokeFunction`) |
| `ResourceConflictException` no `qc publica` | Deploy anterior ainda em andamento | `aws lambda wait function-updated --function-name "$FUNCTION_NAME"` e repita |
| `qc: command not found` ou `FUNCTION_URL vazio` | Sessão nova do CloudShell, ou o `apply` não terminou | `source ~/aie-cloud/aulas/03-serverless-containers/lab/qc.sh` e `qc status` |
| `/produtos` → 500 "falha ao acessar o S3" | `BUCKET_NAME` errado ou CSV fora de `catalogo/` | Ver Plano B da Atividade 2 |
| `Runtime.ImportModuleError` | O zip foi feito fora da pasta (arquivo dentro de subpasta) | Use o `qc publica`, que zipa de dentro da pasta |
| `docker push` → `no basic auth credentials` | Login no ECR expirou (vale 12 h) ou não foi feito | Rode `qc container` de novo (ele refaz o login) |
| Tarefa ECS para com `CannotPullContainerError` | Imagem `:v1` não existe no ECR | Confira `aws ecr describe-images --repository-name produtos-api` |
| Tarefa sobe e cai (`exec format error`) | Imagem buildada para ARM | Rebuild com `--platform linux/amd64` |
| `qc container` espera e desiste | Tarefa não ficou RUNNING | ECS → cluster → Tasks → **Stopped** → motivo; logs no CloudWatch `/ecs/qc-aula03-.../produtos-api` |
| `qc compara` dá timeout no Fargate | Security group ou IP antigo | O IP muda a cada tarefa nova: o `qc compara` busca o IP atual; confira se a tarefa está RUNNING |
| `ExpiredToken` | Sessão do Learner Lab acabou | **Start Lab** e CloudShell novo |

---

## Referências

- [AWS Lambda — Python](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html)
- [Lambda Function URLs](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html)
- [Controle de acesso às Function URLs](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html)
- [Amazon ECR — push de imagem Docker](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html)
- [Amazon ECS no AWS Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [AWS App Runner — mudança de disponibilidade (fechado a novos clientes)](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html)
- [FastAPI](https://fastapi.tiangolo.com/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
