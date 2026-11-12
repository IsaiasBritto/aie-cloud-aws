"""
API de IA da QC — roda na conta AWS do professor, fora do Learner Lab.

O Learner Lab não libera Polly, Transcribe e Comprehend. Esta função expõe os
três atrás de um API Gateway com uma API key por grupo (usage plan com cota),
e as Lambdas dos alunos consomem como qualquer API de terceiro.

Rotas (todas JSON, para não depender de tipos binários no API Gateway):
  GET  /health
  POST /tts         {texto, voz, formato?}       -> {audio_b64, formato: "mp3" ou "wav"}
  POST /stt         {audio_b64, formato, idioma} -> {status, transcricao, segundos}
  POST /sentimento  {textos: [até 25], idioma}   -> {resultados: [{indice, sentimento, scores, entidades}]}
  POST /visao       {imagem_b64}                 -> {tags, texto, objetos, largura, altura}   (só o app da demo)

Limites que vêm do caminho: 29 s de timeout no API Gateway e 6 MB de payload
na Lambda. Por isso a transcrição espera no máximo 24 s e o áudio tem teto de 4 MB.
"""
import base64
import io
import json
import os
import time
import urllib.request
import uuid
import wave

import boto3

BUCKET = os.environ["BUCKET_TEMP"]
VOZES = {"Camila", "Vitoria", "Thiago"}  # vozes neurais pt-BR do Polly
FORMATOS = {"mp3", "mp4", "wav", "flac", "ogg", "amr", "webm", "m4a"}

polly = boto3.client("polly")
transcribe = boto3.client("transcribe")
comprehend = boto3.client("comprehend")
s3 = boto3.client("s3")
rekognition = boto3.client("rekognition")


def _resp(status: int, corpo: dict) -> dict:
    return {"statusCode": status, "headers": {"content-type": "application/json"},
            "body": json.dumps(corpo, ensure_ascii=False)}


def tts(c: dict) -> dict:
    texto = (c.get("texto") or "").strip()
    if not texto or len(texto) > 1500:
        return _resp(400, {"erro": "texto vazio ou maior que 1500 caracteres"})
    voz = c.get("voz", "Camila")
    if voz not in VOZES:
        return _resp(400, {"erro": f"voz '{voz}' indisponível", "vozes": sorted(VOZES)})
    if c.get("formato") == "wav":  # o app da demo toca e reenvia WAV 16 kHz
        pcm = polly.synthesize_speech(Text=texto, VoiceId=voz, Engine="neural", OutputFormat="pcm",
                                      SampleRate="16000")["AudioStream"].read()
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(pcm)
        audio, formato = buf.getvalue(), "wav"
    else:
        audio = polly.synthesize_speech(Text=texto, VoiceId=voz, Engine="neural",
                                        OutputFormat="mp3")["AudioStream"].read()
        formato = "mp3"
    return _resp(200, {"audio_b64": base64.b64encode(audio).decode(), "formato": formato,
                       "voz": voz, "caracteres": len(texto)})


def stt(c: dict) -> dict:
    formato = (c.get("formato") or "mp3").lower()
    if formato not in FORMATOS:
        return _resp(400, {"erro": f"formato '{formato}' não suportado", "aceitos": sorted(FORMATOS)})
    try:
        audio = base64.b64decode(c["audio_b64"])
    except (KeyError, ValueError):
        return _resp(400, {"erro": "envie o áudio em audio_b64"})
    if len(audio) > 4_000_000:
        return _resp(413, {"erro": "áudio maior que 4 MB"})

    # O Transcribe só lê do S3: o áudio passa por um bucket temporário
    job = f"qc-{uuid.uuid4().hex[:10]}"
    chave = f"stt/{job}.{formato}"
    s3.put_object(Bucket=BUCKET, Key=chave, Body=audio)
    try:
        transcribe.start_transcription_job(
            TranscriptionJobName=job, LanguageCode=c.get("idioma", "pt-BR"), MediaFormat=formato,
            Media={"MediaFileUri": f"s3://{BUCKET}/{chave}"})
        inicio = time.time()
        while True:
            st = transcribe.get_transcription_job(TranscriptionJobName=job)["TranscriptionJob"]
            if st["TranscriptionJobStatus"] in ("COMPLETED", "FAILED"):
                break
            if time.time() - inicio > 24:  # o API Gateway corta em 29 s
                return _resp(200, {"status": "IN_PROGRESS",
                                   "dica": "áudio longo para uma chamada síncrona: use um trecho mais curto"})
            time.sleep(1.5)
        if st["TranscriptionJobStatus"] == "FAILED":
            return _resp(422, {"status": "FAILED", "motivo": st.get("FailureReason")})
        with urllib.request.urlopen(st["Transcript"]["TranscriptFileUri"], timeout=10) as r:
            res = json.load(r)
        texto = " ".join(t["transcript"] for t in res["results"]["transcripts"])
        return _resp(200, {"status": "COMPLETED", "transcricao": texto,
                           "segundos": round(time.time() - inicio, 1)})
    finally:
        s3.delete_object(Bucket=BUCKET, Key=chave)
        try:  # o job concluído fica 90 dias listado; apaga para não acumular
            transcribe.delete_transcription_job(TranscriptionJobName=job)
        except Exception:  # noqa: BLE001
            pass


def sentimento(c: dict) -> dict:
    textos = c.get("textos") or []
    if not textos or len(textos) > 25:
        return _resp(400, {"erro": "envie de 1 a 25 textos em 'textos'"})
    idioma = c.get("idioma", "pt")
    sent = comprehend.batch_detect_sentiment(TextList=textos, LanguageCode=idioma)
    ent = comprehend.batch_detect_entities(TextList=textos, LanguageCode=idioma)
    entidades = {r["Index"]: r["Entities"] for r in ent["ResultList"]}
    resultados = [{
        "indice": r["Index"],
        "sentimento": r["Sentiment"],
        "scores": {k.lower(): round(v, 3) for k, v in r["SentimentScore"].items()},
        "entidades": [{"texto": e["Text"], "tipo": e["Type"]} for e in entidades.get(r["Index"], [])],
    } for r in sent["ResultList"]]
    return _resp(200, {"resultados": resultados,
                       "erros": [e["Index"] for e in sent["ErrorList"]]})


def visao(c: dict) -> dict:
    try:
        img = base64.b64decode(c["imagem_b64"])
    except (KeyError, ValueError):
        return _resp(400, {"erro": "envie a imagem em imagem_b64"})
    labels = rekognition.detect_labels(Image={"Bytes": img}, MaxLabels=15, MinConfidence=60)["Labels"]
    textos = rekognition.detect_text(Image={"Bytes": img})["TextDetections"]
    try:
        largura, altura = _dimensoes(img)
    except ValueError:
        largura = altura = None
    objetos = []
    for lab in labels:
        for inst in lab.get("Instances", []):
            b = inst["BoundingBox"]  # proporção 0–1; vira pixel quando sabemos o tamanho
            caixa = ({"x": round(b["Left"] * largura), "y": round(b["Top"] * altura),
                      "w": round(b["Width"] * largura), "h": round(b["Height"] * altura)}
                     if largura else {"x": b["Left"], "y": b["Top"], "w": b["Width"], "h": b["Height"]})
            objetos.append({"label": lab["Name"], "confidence": round(inst["Confidence"] / 100, 3), "box": caixa})
    return _resp(200, {
        "tags": [{"name": lab["Name"], "confidence": round(lab["Confidence"] / 100, 3)} for lab in labels],
        "texto": "\n".join(t["DetectedText"] for t in textos if t["Type"] == "LINE"),
        "objetos": objetos, "largura": largura, "altura": altura})


def _dimensoes(img: bytes) -> tuple[int, int]:
    """Largura e altura de PNG/JPEG sem Pillow (que não está no runtime)."""
    if img[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(img[16:20], "big"), int.from_bytes(img[20:24], "big")
    i = 2
    while i < len(img) - 9:
        if img[i] != 0xFF:
            i += 1
            continue
        marcador, tamanho = img[i + 1], int.from_bytes(img[i + 2:i + 4], "big")
        if marcador in (0xC0, 0xC1, 0xC2):
            return int.from_bytes(img[i + 7:i + 9], "big"), int.from_bytes(img[i + 5:i + 7], "big")
        i += 2 + tamanho
    raise ValueError("formato de imagem não reconhecido")


ROTAS = {("POST", "/tts"): tts, ("POST", "/stt"): stt, ("POST", "/sentimento"): sentimento,
         ("POST", "/visao"): visao}


def lambda_handler(event, context):
    metodo, caminho = event.get("httpMethod"), event.get("path", "")
    # Quem chamou: o id da API key, para ver no log o uso de cada grupo
    chave_id = (event.get("requestContext") or {}).get("identity", {}).get("apiKeyId")
    print(json.dumps({"rota": f"{metodo} {caminho}", "api_key_id": chave_id}))

    if caminho in ("/", "/health"):
        return _resp(200, {"status": "ok", "rotas": [f"{m} {p}" for m, p in ROTAS]})
    fn = ROTAS.get((metodo, caminho))
    if not fn:
        return _resp(404, {"erro": f"rota {metodo} {caminho} não existe"})
    try:
        corpo = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _resp(400, {"erro": "corpo não é JSON"})
    try:
        return fn(corpo)
    except Exception as e:  # noqa: BLE001
        print(f"ERRO {type(e).__name__}: {e}")
        return _resp(500, {"erro": type(e).__name__})
