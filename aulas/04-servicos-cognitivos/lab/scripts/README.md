# Scripts auxiliares — Aula 4

| Script | Quando usar |
|--------|-------------|
| [semear_reviews.py](semear_reviews.py) | **Lab 1** — grava 10 reviews na tabela DynamoDB (sem credencial nenhuma: LabRole) |
| [gerar_audio_tts.py](gerar_audio_tts.py) | **Lab 2** — gera `/tmp/audio-teste.mp3` com o Amazon Polly (voz Camila) para testar a rota `/transcrever` |

## Como usar (AWS CloudShell)

```bash
cd ~/aie-cloud/aulas/04-servicos-cognitivos/lab
source exportar-outputs.sh            # REVIEWS_TABLE, DATA_BUCKET, FUNC_URL...

python3 scripts/semear_reviews.py
python3 scripts/gerar_audio_tts.py
aws s3 cp /tmp/audio-teste.mp3 s3://$DATA_BUCKET/audios/audio-teste.mp3
```

Depois teste: `curl -X POST "${FUNC_URL}transcrever?arquivo=audio-teste.mp3"`.

> Nenhum dos dois scripts usa chave, senha ou host: o boto3 pega a credencial da sessão do CloudShell (LabRole).
