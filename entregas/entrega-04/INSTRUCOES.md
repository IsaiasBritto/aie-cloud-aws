# Entrega 04 — Aula 4 (Serviços Cognitivos & APIs)

**Vale:** 10% da nota final
**Prazo:** até 1 dia antes da Aula 5
**Onde:** upload de UM ZIP no Portal FIAP (combine no grupo quem faz)

---

## O que entregar

| Item | Obrigatório? | Pontos máximos |
|------|--------------|----------------|
| Cabeçalho do grupo + distribuição do trabalho | ✅ Sim | 1 pt (Critério 4) |
| 🟢 N1 — Exercícios 1.1 (pronto/custom/LLM), 1.2 (custo mensal), 1.3 (segurança: IAM Role, Secrets Manager e API key de terceiro), 1.4 (Vision capabilities) | ✅ Sim | 3 pts (Critério 1) |
| 🟡 N2 — 2.1 (pipeline robusto: PII antes do terceiro, aspectos, resumo), 2.2 (casos de Speech na QC), 2.3 (Rekognition pronto vs Custom Labels) | ✅ Sim | 3 pts (Critério 2) + 2 pts qualidade técnica (Critério 3) |
| 🔴 N3 — 3.1 (embeddings reais no pgvector), 3.2 (Rekognition Custom Labels), 3.3 (sumarização com LLM no Bedrock) | 🎁 Bônus | até +2 pts extras |
| Reflexão coletiva ao final | ✅ Sim | 1 pt (Critério 5) |
| **Total** | | **10 pts** |

Conteúdo dos exercícios: [aulas/04-servicos-cognitivos/exercicios.md](../../aulas/04-servicos-cognitivos/exercicios.md).

---

## Estrutura do ZIP

Nome: `entrega-grupo-NN-aula04.zip`.

```
qc-grupo-NN-aula04/
├── entrega-grupo-aula04.md       # ⭐ documento principal (template em ../template-entrega-grupo.md)
├── evidencias-aula04.md          # as saídas salvas em aula (ver abaixo)
├── README.md                     # Como rodar o que foi entregue (qc publica + as rotas novas)
├── terraform/                    # o Terraform do lab, com o que o N2/N3 exigir
├── function/                     # function_app.py com a redação de PII do N2.1 (e rotas do N3, se houver)
└── scripts/                      # Python: re-indexação com embeddings (se N3.1)
```

### Anexos

A API de IA do professor (voz e sentimento) **só funciona durante a aula**. Por isso os anexos se dividem em dois grupos:

| Anexo | Onde vai | Quando é gerado |
|---|---|---|
| Transcrição do `bbc_trecho.mp3` (Lab 2) | `evidencias-aula04.md` | **Em aula**: depois não dá para gerar de novo |
| Saída do `qc tabela reviews` com o sentimento das 10 reviews (Lab 3) | `evidencias-aula04.md` | **Em aula** |
| Campos que o Textract leu da etiqueta (Lab 3) | `evidencias-aula04.md` | Em aula ou depois, num Learner Lab novo |
| Status de moderação das fotos testadas (Lab 4) | `evidencias-aula04.md` | Em aula ou depois, num Learner Lab novo |
| 3 reviews com PII: texto original, texto redigido e o corpo que seria enviado (N2.1, modo `simular`) | `entrega-grupo-aula04.md` | Depois da aula: não precisa da API |
| Prints das métricas do Custom Labels (só se fizer o N3.2) | `entrega-grupo-aula04.md` | Depois da aula |

O grupo que não salvou a transcrição ou o sentimento em aula registra isso no `evidencias-aula04.md` e segue com o resto: o N2.1 vale pelo código e pela redação, não pelo sentimento.

**NÃO incluir:** `terraform.tfstate*`, `.env`, `*.pem`, `__pycache__/`, áudio/imagem binários (>5 MB), chaves de API (nem a do grupo para a API de IA).

---

## Como gerar e enviar

```bash
cd ~/qc-grupo-NN
git pull origin main
git archive --format=zip --prefix=qc-grupo-NN-aula04/ -o ~/entrega-grupo-NN-aula04.zip HEAD:aula04
unzip -l ~/entrega-grupo-NN-aula04.zip
```

Upload no Portal FIAP, tarefa "Entrega Aula 4".

---

## Critérios de avaliação

[Rubrica única](../rubrica.md). **Foco específico desta entrega:**

- **N1:** dominar a tríade **pronta/custom/LLM** e explicar os dois jeitos de a Lambda chegar a um serviço de IA sem chave no código: **pela role** (serviços da própria conta) e pelo **Secrets Manager** (API de terceiro).
- **N2:** o **pipeline robusto de reviews** (PII redigida antes de o texto sair da conta, aspectos e resumo) é o que torna o sentimento útil para o agente da QC tomar decisões reais. **Vision pronto vs Custom** é decisão de produto a ser justificada.
- **N3 (bônus):** o **3.1 (embeddings reais)** é o **fechamento do RAG** começado na Aula 2 — gera vetores reais e re-indexa a tabela `produtos_vetor` do pgvector (Aula 2). É a base do agente conversacional da QC. **Muito valorizado.**
- **Reflexão:** discutir como a **chain pronta + custom + LLM** muda a arquitetura ao longo do ciclo de vida do produto (MVP → escala) e o impacto de custo.

---

## Rotação esperada

Quem fez N1 nas Aulas 1-3 deve preferencialmente assumir **N2** ou **N3** aqui (Critério 4 — Distribuição). O cabeçalho `Distribuição do trabalho` é a evidência.
