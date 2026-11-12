# Código da Lambda — Aula 4

API HTTP da QC com as **tools cognitivas**, servida por uma Function URL, mais um gatilho do S3. Roteamento com o **Powertools for AWS Lambda** (`LambdaFunctionUrlResolver`).

| Rota / gatilho | Lab | Serviço | Autenticação |
|----------------|-----|---------|--------------|
| `GET /health` | | | |
| `POST /falar` `{texto, voz}` | 2 | Polly, pela API de IA da QC | API key do grupo, lida do Secrets Manager |
| `POST /transcrever?arquivo=` | 2 | Transcribe, pela API de IA da QC | idem |
| `POST /analisar-reviews?limit=` | 3 | Comprehend, pela API de IA da QC + DynamoDB | idem |
| `POST /ler-documento?arquivo=` | 3 | Textract (`detect_document_text` e `analyze_document` FORMS) | LabRole |
| `POST /analisar-imagem?arquivo=&produto=` | 4 | Rekognition + DynamoDB `produtos` | LabRole |
| evento de upload em `reviews-fotos/` | 4 | Rekognition `detect_moderation_labels` + DynamoDB `reviews` | LabRole (numa conta normal o S3 invoca; no Learner Lab o `qc foto-review` entrega o mesmo evento, assíncrono) |

## Credenciais

Nenhuma no código. A execution role (LabRole) dá acesso a S3, DynamoDB, Rekognition, Textract e Secrets Manager. A chave da API de IA vem do segredo cujo **nome** está em `SECRET_NAME`; o valor entra pelo `qc chave`, e a função guarda em cache por 5 minutos (e relê se a API devolver 403).

## Deploy (AWS CloudShell)

```bash
source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/qc.sh
qc publica
```

O `qc publica` instala o `requirements.txt` numa pasta em `/tmp` com os pacotes compilados para o Python 3.12 da Lambda (o CloudShell tem outro Python), junta o `function_app.py`, zipa e publica com `aws lambda update-function-code`.
