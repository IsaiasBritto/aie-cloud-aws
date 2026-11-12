# Aula 4 — Serviços de IA da AWS & APIs

## Objetivos de aprendizagem

Ao final desta aula, você será capaz de:

- Consumir APIs de IA prontas da AWS: **Amazon Rekognition** (rótulos, texto e moderação de imagens), **Amazon Textract** (OCR e formulários), e **Polly**, **Transcribe** e **Comprehend** (voz e sentimento) por uma API de terceiro.
- Explicar por que, na AWS, esses serviços **não precisam de recurso provisionado**: são APIs da conta, autorizadas por IAM.
- Autenticar uma Lambda de dois jeitos sem chave no código: pela **execution role**, nos serviços da própria conta, e pelo **Secrets Manager**, na chave de uma API de terceiro.
- Acionar a mesma Lambda por **chamada direta** e por **evento do S3**, e dizer quando usar cada um.
- Decidir entre **API pronta**, **modelo customizado** (Custom Labels, Comprehend Custom) e **LLM** (Amazon Bedrock) para cada caso de uso.

---

## Por que esta aula importa para um AI Engineer

Os agentes da QC precisam **ouvir**, **ler** e **ver**, não só processar texto. As APIs prontas dão essas capacidades em minutos, sem treinar nada. A escolha entre pronta, custom e LLM define **custo, latência e qualidade** da experiência. E quase todo agente consome alguma API de terceiro: saber onde guardar a chave é parte do trabalho.

---

## Conexão com o Quantum Commerce

Esta aula adiciona **novas tools** à API da QC:

| Tool | Serviço | Caminho |
|------|---------|---------|
| `/falar`, `/transcrever` | Polly e Transcribe | API de IA da QC (chave no Secrets Manager) |
| `/analisar-reviews` | Comprehend + DynamoDB | API de IA da QC |
| `/ler-documento` | Textract | LabRole |
| `/analisar-imagem` | Rekognition + DynamoDB | LabRole |
| evento `reviews-fotos/` | Rekognition (moderação) | LabRole, acionada pelo S3 |

---

## Material da aula

| Arquivo | Quando usar |
|---------|-------------|
| [lab/guia-lab.md](lab/guia-lab.md) | Durante a aula: abertura e 4 labs |
| [lab/qc.sh](lab/qc.sh) | `source` uma vez por sessão: cria o comando `qc` |
| [lab/terraform/](lab/terraform/) | Bucket + evento, Lambda + Function URL, duas tabelas DynamoDB, o segredo |
| [lab/check_servicos.sh](lab/check_servicos.sh) | Pré-voo: a sessão chega aos serviços antes do apply? |
| [lab/function/](lab/function/) | Lambda com as tools cognitivas (Powertools) |
| [lab/data/](lab/data/) | Áudio, etiqueta fictícia e fotos de exemplo |
| [lab/app/](lab/app/) | Front-end Streamlit da demo do professor |
| [professor/api-ia/](professor/api-ia/) | A API de IA da QC, na conta do professor |
| [exercicios.md](exercicios.md) | Após a aula: exercícios em 3 níveis |

## Entrega de grupo

Esta aula gera a **4ª entrega de grupo** (10% da nota): instruções em [entregas/entrega-04/](../../entregas/entrega-04/). Rubrica em [entregas/rubrica.md](../../entregas/rubrica.md).

---

## Pré-requisitos

- ✅ Learner Lab iniciado, CloudShell e Terraform no `$HOME`
- ✅ Nenhuma dependência das aulas anteriores: **esta aula é autossuficiente**
- ✅ A URL e a chave da API de IA, entregues pelo professor a cada grupo

> **O que o Learner Lab não libera:** Polly, Transcribe, Comprehend, Translate e Bedrock. Voz e sentimento chegam pela API de IA da QC, hospedada pelo professor; o Bedrock aparece aqui como contexto (e nos exercícios de N3) e entra de verdade na Aula 5.
