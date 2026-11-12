# Arquivos de exemplo — Aula 4

| Arquivo | Lab | Para quê | Origem |
|---------|-----|----------|--------|
| `bbc_trecho.mp3` | 2 | Fala real em português para `qc transcreve` (40 s, 320 KB) | Trecho do podcast da BBC News Brasil descrito em `bbc_exemplo.json`, baixado com `bbc_download.py`, para uso em aula |
| `etiqueta.png` | 3 | Etiqueta de envio **fictícia** da QC para o Textract (`qc documento`) | Gerada para a disciplina; nomes e endereço inventados |
| `produto.jpg` | 4 | Foto de produto para o catálogo (`qc catalogo`) e foto "limpa" de review | Já estava no repositório |
| `review-foto-praia.jpg` | 4 | Foto de review que a moderação manda para revisão (`qc foto-review`) | Amostra `yoga_swimwear.jpg` do repositório [aws-samples/amazon-rekognition-code-samples](https://github.com/aws-samples/amazon-rekognition-code-samples) (licença MIT-0), reduzida para 1200 px |

O áudio da BBC inteiro (6 MB) saiu do repositório: o `$HOME` do CloudShell tem só 1 GB, e o caminho até a API de IA aceita no máximo 4 MB de áudio por chamada.
