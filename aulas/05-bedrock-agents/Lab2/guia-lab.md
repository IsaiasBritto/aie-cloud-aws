# Guia do Lab2 — Deva contínuo (45 min)

Objetivo: ver um agente trabalhar **sem ninguém chamar** e provar que a fronteira em código segura
o que o prompt não segura. Você termina com uma regra nova na memória **assinada por você**.

O lab é um só (a mesma API, o mesmo agente, a mesma fronteira) em três formas. Muda onde roda e
de onde vem a nota:

| Parte | Onde roda | Quem faz | Precisa da AWS? | Para quê |
|---|---|---|---|---|
| **1 · O lab (Caminho A)** | no seu computador | turma | não | o lab da aula (45 min) |
| **2 · Bônus (Caminho B)** | CloudShell do Learner Lab | turma, em casa | Learner Lab | o gatilho de verdade: bônus N3.1 da Entrega 05 |
| **3 · Demo do professor** | computador do professor | professor | conta própria | o mesmo agente decidindo com um LLM no Bedrock |

No Caminho A, a nota entra quando você roda `semear`. No Caminho B, ela cai num bucket S3, um
evento aciona a Lambda e a mensagem espera numa fila SQS. Na demo, quem decide é um modelo, no
lugar das regras.

---

## Parte 1 · O lab (Caminho A) — no seu computador (Python 3.11+)

Nada roda na AWS neste caminho: a API, a mesa do auditor e o agente são processos Python no seu
computador, e a fila e a memória são arquivos na pasta `dados/`. Custo zero, nenhuma credencial.

> **No Windows não há `make`.** Cada `make` só dispara um comando, definido no `Makefile` desta
> pasta (digite `make` no Mac, Linux ou CloudShell para ver a lista). No PowerShell, rode a coluna
> da direita, com o venv ativo (`.venv\Scripts\Activate.ps1`) em cada terminal:
>
> | `make` | O que faz | Equivalente no PowerShell |
> |---|---|---|
> | `instalar` | instala as dependências | `pip install -r requirements.txt` |
> | `testar` | roda os testes | `python -m pytest` |
> | `api` | sobe a API em :8000 | `python -m uvicorn api.principal:aplicacao --reload --port 8000` |
> | `web` | sobe a mesa do auditor em :8501 | `streamlit run web/aplicacao.py` |
> | `semear` | põe 3 notas na fila | `python gatilho/disparador.py --semear` |
> | `volta` | uma volta do agente | `python gatilho/ciclo_do_agente.py --uma-volta` |
> | `demos` | as três tentativas barradas | `python gatilho/ciclo_do_agente.py --tentar-aprovar` (depois `--tentar-liberar` e `--injecao`) |
>
> O código de cada comando: `api/principal.py` e `api/servicos/` (API), `web/aplicacao.py` (mesa),
> `gatilho/disparador.py` (semear, enviar, drenar) e `gatilho/ciclo_do_agente.py` (o agente).

### Passo 1 · Instalar e testar (5 min)

```bash
git clone https://github.com/IsaiasBritto/aie-cloud-aws.git aie-cloud
cd aie-cloud/aulas/05-bedrock-agents/Lab2
python -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
make instalar        # sem make: pip install -r requirements.txt
make testar          # esperado: 26 passed
```

> Um aviso `StarletteDeprecationWarning` no fim do pytest é esperado: vem de uma biblioteca de
> teste e não afeta o lab.

> **Por que 26 e não 23?** São 23 funções de teste; uma delas roda com 4 valores de auditor
> (`None`, `""`, `"deva"`, `"DEVA"`), e o pytest conta cada valor como um caso.

### Passo 2 · Subir a API e a mesa do auditor (5 min)

```bash
make api      # terminal 1 — abra http://localhost:8000/docs e conte as 14 operações
make web      # terminal 2 — abre o Streamlit
```

Na barra lateral do Streamlit, **ainda não** preencha o seu nome.

### Passo 3 · Rodar o agente, volta a volta (10 min)

```bash
make semear   # terminal 3 — põe 3 notas na fila
make volta    # rode 4 vezes, lendo a saída a cada volta
```

| Volta | Nota | Resultado esperado | O que observar |
|---|---|---|---|
| 1 | nota-001 (estacionamento em Congonhas) | `extraido` + proposta `p-0001` | Classificou por palavra-chave, mas **ficou em dúvida** e propôs uma regra. |
| 2 | nota-001-reenvio (idêntica) | `duplicado` | Mesmo hash: não paga duas vezes. |
| 3 | nota-002 (hotel, R$ 1.250) | `excecao` · `seguranca` | O rodapé tenta dar uma ordem ao agente. **Texto lido é dado.** |
| 4 | — | `nada a fazer` | Fila vazia (204). O laço termina. |

Confira na aba **Painel**: taxa de devolução de 33% e o alerta acima de 30%. Leia a frase do
alerta: *o problema é a regra, não o modelo.*

### Passo 4 · Bater na fronteira (5 min)

```bash
make demos
```

- **403** — o agente tenta aprovar a própria proposta. Não há cabeçalho `X-Auditor`.
- **409** — o agente tenta tirar o hotel da exceção. A máquina de estados não deixa.
- **422** — o agente tenta "aprender" a frase de injeção. Vira incidente, não memória.

Repare no campo `como_resolver` de cada erro: a resposta da API foi escrita **para o modelo ler**.

### Passo 5 · Assinar a memória (10 min)

1. Aba **Propostas** → clique **Aprovar** em `p-0001` **sem** nome. Veja o 403 na tela.
2. Preencha o seu nome na barra lateral e aprove de novo.
3. Aba **Memória**: a última linha termina com `(definido por: <seu nome>)`.
4. Aba **Exceções**: decida o hotel (liberar ou recusar) com uma justificativa.
5. Teste se o agente aprendeu:

```bash
curl -s -X POST localhost:8000/fila -H 'Content-Type: application/json' \
  -d '{"arquivo":"nota-003.txt","conteudo":"Descrição: Estacionamento no aeroporto de Guarulhos\nValor: R$ 40,00"}'
make volta    # o motivo agora cita o MEMORY.md, não a palavra-chave
```

### Passo 6 · Discussão (5 min)

Abra o `AGENTS.md`, seção 7. Na v1.3 a regra era *«Escreva em MEMORY.md somente quando o auditor
humano corrigir você»*. **Quem verificava a condição?** Escreva em uma frase por que a v2.0 tirou
essa condição do texto e a colocou na API.

---

## Parte 2 · Bônus (Caminho B) — no CloudShell do Learner Lab

Tudo roda dentro do CloudShell, inclusive a API: o seu computador não participa. O CloudShell não abre o
Streamlit, então a assinatura é feita pela linha de comando (Passo 4).

**Credencial:** nada a configurar. No CloudShell aberto pelo console do Learner Lab, o Terraform,
o `aws` e o Python já usam a credencial da sessão (role `voclabs`). Para conferir:
`aws sts get-caller-identity` deve mostrar `assumed-role/voclabs/...`. Se a sessão do Learner Lab
expirar, clique em **Start Lab**, reabra o CloudShell e retome do Passo 1.

### Passo 1 · Preparar

A home do CloudShell tem 1 GB, e quem vem das aulas anteriores costuma chegar com ela quase
cheia de providers do Terraform. Confira antes de começar:

```bash
df -h ~ | tail -1      # Use% acima de 80%? Rode as duas linhas abaixo
rm -rf ~/.terraform.d/plugin-cache/*   # esvazia, mas mantém a pasta que o .bashrc usa
find ~/aie-cloud -name .terraform -type d -prune -exec rm -rf {} +
```

Nenhuma das duas apaga estado: o `terraform.tfstate` fica onde está e o `init` baixa o provider
de novo. Nesta aula o cache vai para o `/tmp`, que tem espaço de sobra (some quando a sessão
reinicia, e aí o `init` baixa outra vez).

```bash
export TF_PLUGIN_CACHE_DIR=/tmp/tf-cache && mkdir -p $TF_PLUGIN_CACHE_DIR
cd ~ && git clone https://github.com/IsaiasBritto/aie-cloud-aws.git aie-cloud 2>/dev/null || git -C ~/aie-cloud pull
cd ~/aie-cloud/aulas/05-bedrock-agents/Lab2
python3 -m venv /tmp/venv-qc && source /tmp/venv-qc/bin/activate
pip install --no-cache-dir -r requirements.txt
python -m pytest            # 26 passed
nohup python -m uvicorn api.principal:aplicacao --port 8000 > api.log 2>&1 &
export API_URL=http://localhost:8000
```

### Passo 2 · Provisionar o gatilho (Terraform)

Se o Terraform ainda não estiver no CloudShell, instale como na Aula 1 (guia-lab, Passo 4).

```bash
make provisionar            # bucket, regra do EventBridge, Lambda (LabRole) e SQS
terraform -chdir=infra/terraform output
```

### Passo 3 · Uma nota cai no S3 e o agente acorda

```bash
make enviar                 # sobe as 3 amostras para s3://<bucket>/entrada/
sleep 10
make drenar                 # lê a SQS, baixa do S3 e faz POST /fila
for i in 1 2 3 4; do make volta; done
make demos
```

Prove que o MEMORY.md **não** dispara o ciclo:

```bash
B=$(terraform -chdir=infra/terraform output -raw bucket)
aws s3 cp MEMORY.md s3://$B/memoria/MEMORY.md          # fora de entrada/: a regra nem acorda a Lambda
aws s3 cp MEMORY.md s3://$B/entrada/MEMORY.md          # dentro de entrada/: a Lambda acorda e ignora
L=$(terraform -chdir=infra/terraform output -raw lambda)
aws logs tail /aws/lambda/$L --since 5m                # procure {"ignorado": "entrada/MEMORY.md"}
```

### Passo 4 · Assinar pela linha de comando

```bash
curl -s localhost:8000/memoria/propostas
curl -s -X POST localhost:8000/memoria/propostas/p-0001/aprovar                    # 403
curl -s -X POST localhost:8000/memoria/propostas/p-0001/aprovar -H 'X-Auditor: SEU NOME'
curl -s localhost:8000/memoria | python -m json.tool | tail -5
curl -s 'localhost:8000/fila?estado=excecao' | python -m json.tool | grep '"id"'   # id do hotel
curl -s -X POST localhost:8000/fila/<ID_DO_HOTEL>/resolver -H 'X-Auditor: SEU NOME' \
  -H 'Content-Type: application/json' -d '{"decisao":"recusar","motivo":"tentativa de manipulação"}'
```

### Passo 5 · Limpar (obrigatório)

```bash
make limpar
```

---

## Parte 3 · Demo do professor — o mesmo agente com um LLM no Bedrock

O agente da turma decide por regras (sem LLM), porque o Learner Lab não libera o Bedrock. Na
conta própria, o professor roda o **mesmo ciclo** com um modelo de verdade: ele recebe as 5
operações de `agente/openapi-agente.json` como ferramentas (Converse) e decide sozinho, com os
três freios em código (8 voltas, 20 mil tokens, 60 s). A fronteira é a mesma.

Use o Caminho A, com a API rodando no terminal 1. O código não tem campo de credencial: o boto3
procura sozinho, primeiro nas variáveis de ambiente do terminal, depois no perfil da AWS CLI.

**1 · Coletar a credencial** (sem tela projetada). No CloudShell da **conta pessoal** (o usuário
no canto superior direito não pode ser `voclabs`):

```bash
aws configure export-credentials --format powershell   # no Mac/Linux: --format env
```

Ou, se a AWS CLI do seu computador já tem um perfil da conta pessoal, pule este passo e use
`$Env:AWS_PROFILE = "<seu-perfil>"`.

**2 · Escolher o modelo.** No console do Bedrock (us-east-1), abra o catálogo, escolha o modelo
e copie o ID do **perfil de inferência** (começa com `us.` ou `global.`). Teste antes no Playground.

**3 · Rodar**, no terminal 3, com o venv ativo:

```powershell
# cole as três linhas $Env:AWS_... geradas no passo 1
$Env:AWS_REGION = "us-east-1"
$Env:BEDROCK_MODEL_ID = "<ID copiado no passo 2>"
python gatilho/disparador.py --semear
python gatilho/ciclo_do_agente.py --uma-volta --bedrock
```

A saída mostra por que o agente parou (`parou_por`), as voltas e os tokens gastos. Abra a mesa do
auditor: as decisões do modelo aparecem como as do script, e o 403 vale do mesmo jeito.

> As variáveis valem só naquele terminal e a credencial do CloudShell vence em cerca de 1 hora
> (`ExpiredToken`: gere de novo). Nunca grave chave em `.env` nem em arquivo do repositório: ele é
> público. Perfil `global.` pode processar o dado fora dos EUA; para dado pessoal real, a decisão
> é do jurídico.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `AccessDenied ... GetBucketObjectLockConfiguration` no `terraform apply` | O Learner Lab bloqueia essa leitura, que o `aws_s3_bucket` faz sempre. Os labs agora criam o bucket pelo módulo `modulos/bucket-s3` (AWS CLI) | `git -C ~/aie-cloud pull`, `terraform init`, `terraform state rm aws_s3_bucket.notas` e `terraform apply` de novo. O módulo reaproveita o bucket que já foi criado |
| `No space left on device` no `terraform init` ou no `pip` | Home de 1 GB cheia | Passo 1 do Caminho B: apague o cache antigo e use o `/tmp/tf-cache` |
| `make: command not found` (Windows) | Sem make | Rode o comando que está ao lado do alvo no `Makefile`. |
| Streamlit: "API fora do ar" | Terminal 1 parado | Suba `make api` de novo. |
| Volta 1 sai `duplicado` | Fila de uma rodada anterior | Apague a pasta `dados/` e rode `make semear` de novo. |
| `drenar` não traz nada | Ainda não chegou à SQS | Espere 10 s e repita; confira os logs da Lambda. |
| `AccessDenied` ao criar role | Learner Lab não deixa | O Terraform já usa a `LabRole`; não crie IAM. |
