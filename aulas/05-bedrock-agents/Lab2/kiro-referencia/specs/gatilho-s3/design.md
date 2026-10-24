# Desenho — gatilho S3 do Lab2

## Visão geral
```
S3 entrada/ ─Object Created─▶ EventBridge (regra: prefixo entrada/) ─▶ Lambda ─▶ SQS
                                                                              │
                         disparador.py --sqs ◀────────────────────────────────┘
                              └─▶ GET objeto no S3 ─▶ POST /fila
```

## Decisões
| Decisão | Por quê | Requisito |
|---|---|---|
| Filtro **na regra do EventBridge**, não só na Lambda | Barrar na borda custa menos que acordar a Lambda | 1.2 |
| Segundo filtro em `deve_disparar()` na Lambda | Se alguém afrouxar a regra, o MEMORY.md continua sem disparar | 1.2 |
| **SQS** entre a Lambda e a API | A Lambda roda na AWS e não alcança a API do laptop/CloudShell; a fila também segura a nota se a API cair | 1.1, 1.4 |
| Deduplicação por **hash do conteúdo**, na API | Reenvio com outro nome de arquivo continua sendo o mesmo documento | 1.3 |
| `force_destroy` no bucket e `99-remover-tudo.sh` | Learner Lab tem orçamento; limpar tem que ser um comando | — |

## Tratamento de erro
- Mensagem da SQS só é apagada **depois** do `POST /fila` com sucesso.
- `visibility_timeout` de 120 s: se o disparador cair no meio, a mensagem volta.

## Estratégia de teste
- `deve_disparar()`: `entrada/x.pdf` sim; `memoria/MEMORY.md`, `entrada/MEMORY.md`, `saida/...` não.
- Ponta a ponta com `TestClient`: semear → 4 voltas → extraido, duplicado, excecao, nada a fazer.
