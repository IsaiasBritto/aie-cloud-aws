# Tarefas — gatilho S3 do Lab2

- [ ] 1. Regra do EventBridge com prefixo `entrada/` e notificação EventBridge no bucket
  - _Requisitos: 1.1, 1.2_
- [ ] 2. Lambda `lambda_gatilho.py` que filtra de novo e envia `{bucket, chave, etag}` para a SQS
  - _Requisitos: 1.1, 1.2, 2.1_
- [ ] 3. `disparador.py --sqs`: drena a fila, lê o objeto no S3 e faz `POST /fila`
  - _Requisitos: 1.1, 1.4_
- [ ] 4. Deduplicação por hash do conteúdo na API (`possivel_duplicado_de`)
  - _Requisitos: 1.3_
- [ ] 5. Testes: MEMORY.md não dispara; duplicado não reprocessa; ciclo de ponta a ponta
  - _Requisitos: 1.2, 1.3_
