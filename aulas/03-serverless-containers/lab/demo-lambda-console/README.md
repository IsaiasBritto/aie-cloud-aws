# Demo: uma função Lambda criada na mão, pelas telas da AWS

Demonstração do professor para a Aula 3, antes do Lab 1. A turma acompanha no projetor; quem quiser repete no próprio Learner Lab depois.

Tudo acontece navegando pelas telas da AWS (o AWS Management Console), com o editor de código da própria Lambda: sem Terraform, sem terminal e sem o comando `qc`. A ideia é mostrar, clicando, o que uma função Python precisa para virar uma Lambda: a identidade, o código, o teste, a configuração, o log e a URL. No Lab 1, o Terraform e o `qc` fazem essas mesmas coisas por nós.

A função é a `consultar_estoque` do slide de recap ("Funções · Recap Python"), agora com um `lambda_handler` na frente: [lambda_function.py](lambda_function.py).

Tempo: uns 15 minutos. Custo: zero na prática (algumas chamadas e poucos KB de log).

> Os nomes dos botões estão em inglês, como aparecem no console. Região: `us-east-1`.

---

## 1. Criar a função

1. No console, procure **Lambda** e clique em **Create function**. A tela se chama **Create Event Function**.
2. Deixe marcado **Author from scratch**.
3. **Function name:** `demo-estoque`.
4. **Runtime:** **Python 3.14** (o padrão da tela serve).
5. Abra **Additional settings** e, em **Execution role**, escolha a role existente **LabRole**.
6. Clique em **Create Event Function**.

Se você clicar em criar sem o passo 5, aparece o erro `not authorized to perform: iam:CreateRole`: por padrão a tela tenta criar uma role nova, e o Learner Lab não deixa. Basta abrir **Additional settings**, escolher a LabRole e criar de novo.

Toda Lambda roda com uma identidade, a execution role, que vira credencial temporária dentro da função. No Learner Lab não dá para criar roles; por isso usamos a LabRole, que já existe na conta. Fora do Learner Lab, o console criaria uma role nova só com permissão de escrever log.

## 2. Colar o código e publicar

1. Na aba **Code**, o editor abre o `lambda_function.py` com um "hello world".
2. Apague tudo e cole o conteúdo de [lambda_function.py](lambda_function.py).
3. Clique em **Deploy**. Enquanto não clicar, o código está só no editor; a função continua com o anterior.

Mostre as duas partes do arquivo: a `consultar_estoque`, que é Python comum e não sabe que está na nuvem, e o `lambda_handler(event, context)`, que é o ponto de entrada. Logo abaixo do editor, em **Runtime settings**, o **Handler** aparece como `lambda_function.lambda_handler`: arquivo `lambda_function`, função `lambda_handler`.

## 3. Testar pelo console

1. Clique em **Test** (no editor, ou na aba **Test**).
2. **Create new test event**, nome `estoque-sp`, com este JSON:

   ```json
   {"produto_id": "P001", "armazem_id": "SP"}
   ```

3. Salve e clique em **Test** de novo.

O resultado mostra a **Response** (com `statusCode`, `headers` e `body`), os **Function Logs** (o `print` da função e a linha `REPORT`) e, na primeira chamada, o **Init Duration**: é o cold start. Clique em **Test** outra vez e repare que o Init Duration some.

Crie mais dois eventos para mostrar os outros caminhos do código:

| Evento | JSON | O que volta |
|---|---|---|
| `estoque-rj` | `{"produto_id": "P001", "armazem_id": "RJ"}` | café sem estoque (`em_estoque: false`) |
| `sem-produto` | `{}` | `statusCode` 400, "informe produto_id" |

## 4. Ajustar memória e timeout

1. Aba **Configuration** → **General configuration** → **Edit**.
2. **Memory:** 128 MB. **Timeout:** 10 s. **Save**.

São as duas alavancas de custo e de comportamento da função. Na Lambda, a CPU cresce junto com a memória; o timeout é quanto tempo a função pode rodar antes de ser interrompida.

## 5. Ver o log

1. Aba **Monitor** → **View CloudWatch logs**.
2. Abra o **log stream** mais recente.

Cada chamada tem um `START`, o `print` da função e uma linha `REPORT` com duração, memória usada e o tempo cobrado. O log group `/aws/lambda/demo-estoque` foi criado pela própria Lambda.

## 6. Dar uma URL pública à função

1. Aba **Configuration** → **Function URL** → **Create function URL**.
2. **Auth type:** **NONE**. **Save**.
3. Copie a URL e abra no navegador, acrescentando os parâmetros:

   ```
   https://<id>.lambda-url.us-east-1.on.aws/?produto_id=P002&armazem_id=SP
   ```

Agora a mesma função atende uma chamada HTTP. Os parâmetros chegam em `queryStringParameters`, e é a primeira linha do `lambda_handler` que trata os dois casos (teste do console e URL).

Com **NONE**, qualquer pessoa com a URL chama a função. Para uma demo serve; para uma ferramenta de agente em produção, a pergunta é quem deveria poder chamá-la. Em **Configuration** → **Permissions** → **Resource-based policy statements** aparecem as permissões que o console criou para a URL. Se o navegador mostrar `Forbidden`, é ali que falta alguma: desde outubro de 2025, a URL pública precisa de `lambda:InvokeFunctionUrl` e de `lambda:InvokeFunction`.

## 7. Mudar o código e publicar de novo

1. Na aba **Code**, troque a quantidade do café em SP (por exemplo, de 42 para 7).
2. **Deploy**.
3. Rode o teste `estoque-sp` de novo e recarregue a URL no navegador.

É o que o `qc publica` faz no Lab 1, só que pelo CLI: manda o código novo e espera a função atualizar.

## 8. Limpar

1. **Lambda** → `demo-estoque` → **Actions** → **Delete** → confirme.
2. **CloudWatch** → **Logs** → **Log Management** → `/aws/lambda/demo-estoque` → **Actions** → **Delete log group(s)**.

Apagar a função leva junto a URL e as permissões. O log group fica, e cobra armazenamento, até ser apagado. No Terraform do lab, o log group nasce com retenção de 7 dias por esse motivo.

---

## O que o Terraform e o `qc` fazem por você no Lab 1

| Na mão (esta demo) | No Lab 1 |
|---|---|
| Create function, com a LabRole | `aws_lambda_function` no `lambda.tf`, com `data "aws_iam_role" "lab"` |
| Colar o código e Deploy | `qc publica v1` / `qc publica v2` |
| Test com um evento JSON | `qc chama` |
| General configuration: memória e timeout | `memory_size` e `timeout` no `lambda.tf` |
| Function URL com Auth type NONE | `aws_lambda_function_url` + as duas permissões |
| Log group criado pela Lambda, sem retenção | `aws_cloudwatch_log_group` com 7 dias |
| Delete da função e do log group | `terraform destroy` |

## Se der erro

| Sintoma | O que fazer |
|---|---|
| `not authorized to perform: iam:CreateRole` ao criar | A tela tentou criar uma role nova: abra **Additional settings** e escolha a **LabRole** |
| Não aparece a LabRole na lista de roles | A sessão do Learner Lab precisa estar ativa; recarregue a tela |
| O teste devolve a resposta antiga | Faltou clicar em **Deploy** depois de editar |
| `Runtime.ImportModuleError` | O arquivo foi renomeado ou o **Handler** em Runtime settings não é `lambda_function.lambda_handler` |
| A URL mostra `Forbidden` | Falta uma das duas permissões da URL (ver passo 6) |
| `Task timed out` | O timeout ficou baixo demais; volte ao passo 4 |
| A sessão caiu e aparece `voc-cancel-cred` | **Start Lab** de novo; a função continua lá |
