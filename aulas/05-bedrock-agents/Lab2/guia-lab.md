# Guia do Lab2 — Deva contínuo (45 min)

Objetivo: ver um agente trabalhar **sem ninguém chamar** e provar que a fronteira em código segura
o que o prompt não segura. Você termina com uma regra nova na memória **assinada por você**.

Escolha um caminho:

- **Caminho A — sua máquina** (recomendado): API + mesa do auditor no navegador.
- **Caminho B — CloudShell**: sem instalar nada; tudo por linha de comando. Inclui o gatilho na AWS.

---

## Caminho A — sua máquina (Python 3.11+)

### Passo 1 · Instalar e testar (5 min)

```bash
git clone https://github.com/IsaiasBritto/aie-cloud-aws.git
cd aie-cloud-aws/aulas/05-bedrock-agents/Lab2
python -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
make instalar        # sem make: pip install -r requirements.txt
make testar          # esperado: 25 passed
```

> **Por que 25 e não 22?** São 22 funções de teste; uma delas roda com 4 valores de auditor
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

## Caminho B — CloudShell (Learner Lab)

O CloudShell não abre o Streamlit, mas roda a API, o agente e o gatilho de verdade.

### Passo 1 · Preparar

```bash
git clone https://github.com/IsaiasBritto/aie-cloud-aws.git
cd aie-cloud-aws/aulas/05-bedrock-agents/Lab2
python3 -m venv /tmp/venv-qc && source /tmp/venv-qc/bin/activate
pip install --no-cache-dir -r requirements.txt
python -m pytest            # 25 passed
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

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `AccessDenied ... GetBucketObjectLockConfiguration` no `terraform apply` | O Learner Lab bloqueia essa leitura, que o `aws_s3_bucket` faz sempre. Os labs agora criam o bucket pelo módulo `modulos/bucket-s3` (AWS CLI) | `git -C ~/aie-cloud pull`, `terraform init`, `terraform state rm aws_s3_bucket.notas` e `terraform apply` de novo. O módulo reaproveita o bucket que já foi criado |
| `make: command not found` (Windows) | Sem make | Rode o comando que está ao lado do alvo no `Makefile`. |
| Streamlit: "API fora do ar" | Terminal 1 parado | Suba `make api` de novo. |
| Volta 1 sai `duplicado` | Fila de uma rodada anterior | Apague a pasta `dados/` e rode `make semear` de novo. |
| `drenar` não traz nada | Ainda não chegou à SQS | Espere 10 s e repita; confira os logs da Lambda. |
| `AccessDenied` ao criar role | Learner Lab não deixa | O Terraform já usa a `LabRole`; não crie IAM. |
