---
inclusion: fileMatch
fileMatchPattern: "api/**/*.py"
---
## Regras da API do Lab2
- Toda operação nova entra em api/principal.py E nos testes.
- O agente NUNCA ganha rota de aprovação: o 403 é o contrato.
- Exceção não volta para 'deva': a transição é proibida em código.
- Rode pytest api/testes antes de dar a tarefa por pronta.
