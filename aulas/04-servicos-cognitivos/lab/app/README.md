# QC Cognitive Studio — front-end da Aula 4 (demo do professor)

Aplicação Streamlit que consome Polly, Transcribe e Rekognition e explora texto → fala, fala → texto, análise de imagem e localização espacial.

O ponto da demo não é a interface. É a comparação: **cada operação pode ser executada por dois caminhos**, e o app mostra os dois lado a lado.

| | Via API de IA | Direto na AWS |
|---|---|---|
| Credencial no cliente | API key da API de IA | access key de um usuário IAM |
| O que ela abre | 4 rotas, com cota diária | tudo o que a política do usuário permite |
| Revogar | tirar só essa chave | desativar a access key de todo mundo que a usa |
| Latência | um salto a mais | um salto a menos |

O app aponta para a API de [professor/api-ia](../../professor/api-ia/README.md), publicada na conta do professor: o Learner Lab não libera Polly nem Transcribe.

## Rodar

Na **sua máquina** — não no CloudShell. O navegador só libera o microfone em `localhost` ou HTTPS.

```bash
cd aulas/04-servicos-cognitivos/lab/app
pip install -r requirements.txt
streamlit run app.py
```

Abre em `http://localhost:8501`.

## Preencher a barra lateral

Na pasta `professor/api-ia/terraform`, depois do apply:

```bash
terraform output url
terraform output -json chaves      # use a chave "professor"
```

A **URL** e a **API key** bastam para o caminho pela API. A access key, o token e o `DATA_BUCKET` servem só ao caminho direto, numa conta onde Polly e Transcribe funcionam.

## As quatro abas

**🔊 Texto → Fala.** Sintetiza com vozes neurais do Polly (Camila, Vitória, Thiago...). O WAV pode ser baixado e serve de entrada para a próxima aba.

**🎤 Fala → Texto.** Grava do microfone ou aceita upload. O app converte para WAV 16 kHz mono antes de enviar. O Transcribe processa em **lote** (o áudio passa pelo S3): espere alguns segundos.

**🖼️ Visão + Espacial.** Rótulos, texto (OCR) e objetos com caixa, desenhados sobre a imagem original com Pillow. O Rekognition devolve as caixas em **proporção** (0–1); a API e o app convertem para pixels.

**🏛️ Arquitetura.** A tabela comparativa e as perguntas de discussão.

## O que este app deliberadamente não faz

Não guarda credencial em disco, não usa `.env` e não tem "lembrar credenciais". Tudo vive na sessão do navegador e some quando a aba fecha.

## Rotas que ele consome

Todas com o cabeçalho `x-api-key`:

| Rota | Corpo | Devolve |
|---|---|---|
| `POST /tts` | `{"texto","voz","formato":"wav"}` | `{"audio_b64"}` (WAV 16 kHz) |
| `POST /stt` | `{"audio_b64","formato":"wav","idioma"}` | `{"transcricao"}` |
| `POST /visao` | `{"imagem_b64"}` | `{"tags","texto","objetos","largura","altura"}` |
