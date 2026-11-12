"""
Lambda da Aula 4 — os sentidos do agente da Quantum Commerce.

Duas origens de IA, dois jeitos de autenticar:

  * Na conta do Learner Lab (Rekognition e Textract): a função chama pela
    execution role (LabRole). Nenhuma chave no código.
  * Na API de IA da QC (voz e sentimento: Polly, Transcribe e Comprehend, que o
    Learner Lab não libera): um serviço de terceiro, que exige API key. A chave
    do grupo fica no Secrets Manager; a função lê o segredo pela LabRole. Também
    nenhuma chave no código.

Rotas (Function URL, roteamento com Powertools):
  GET  /health
  POST /falar                JSON {texto, voz}  -> MP3 no S3 (audios/)  Lab 2
  POST /transcrever?arquivo=fala.mp3           -> texto                Lab 2
  POST /analisar-reviews?limit=10              -> sentimento no DynamoDB   Lab 3
  POST /ler-documento?arquivo=etiqueta.png     -> OCR × campos (Textract)  Lab 3
  POST /analisar-imagem?arquivo=produto.jpg   -> tags no DynamoDB     Lab 4

E um gatilho que não é rota: o upload em reviews-fotos/ dispara a função pelo
evento do S3, e ela modera a foto (Rekognition) e marca a review.     Lab 4
"""
import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from decimal import Decimal

import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.event_handler import LambdaFunctionUrlResolver, Response

logger = Logger()
app = LambdaFunctionUrlResolver(serializer=lambda o: json.dumps(o, ensure_ascii=False, default=str))

DATA_BUCKET = os.environ["DATA_BUCKET"]
REVIEWS_TABLE = os.environ["REVIEWS_TABLE"]
PRODUTOS_TABLE = os.environ["PRODUTOS_TABLE"]
SECRET_NAME = os.environ["SECRET_NAME"]

# Clientes criados fora do handler: reaproveitados entre invocações quentes
s3 = boto3.client("s3")
rekognition = boto3.client("rekognition")
textract = boto3.client("textract")
secrets = boto3.client("secretsmanager")
dynamodb = boto3.resource("dynamodb")


# ------------------------------------------------------- utilidades

def _erro(msg: str, status: int = 500, **extra) -> Response:
    return Response(status_code=status, content_type="application/json",
                    body=json.dumps({"erro": msg, **extra}, ensure_ascii=False))


def _dec(x: float) -> Decimal:
    """O DynamoDB não aceita float: número decimal vai como Decimal."""
    return Decimal(str(round(x, 3)))


# ------------------------------------------- a API de IA da QC (terceiro)

class SemChave(Exception):
    """O segredo existe, mas o grupo ainda não gravou a chave nele (qc chave)."""


_cache = {"valor": None, "lido_em": 0.0}


def _credencial_api() -> dict:
    """URL e chave da API de IA, lidas do Secrets Manager pela LabRole.

    Cache de 5 minutos: cada leitura do segredo custa uma chamada (e US$ 0,05
    por 10 mil). Se a chave for trocada, a função pega a nova em até 5 min.
    """
    if _cache["valor"] and time.time() - _cache["lido_em"] < 300:
        return _cache["valor"]
    try:
        bruto = secrets.get_secret_value(SecretId=SECRET_NAME)["SecretString"]
    except secrets.exceptions.ResourceNotFoundException as e:
        # Segredo criado pelo Terraform, mas ainda sem valor
        raise SemChave from e
    valor = json.loads(bruto)
    _cache.update(valor=valor, lido_em=time.time())
    return valor


def _api_ia(rota: str, corpo: dict, tentativa: int = 1) -> dict:
    """POST JSON na API de IA da QC, com a API key do grupo no cabeçalho."""
    cred = _credencial_api()
    req = urllib.request.Request(
        cred["url"].rstrip("/") + rota,
        data=json.dumps(corpo).encode(),
        headers={"content-type": "application/json", "x-api-key": cred["chave"]},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=28) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 403 and tentativa == 1:
            # A chave pode ter sido trocada (qc chave de novo): esquece o cache e relê
            _cache["valor"] = None
            return _api_ia(rota, corpo, tentativa=2)
        # 403: chave errada ou revogada · 429: cota do grupo esgotada
        detalhe = e.read().decode(errors="replace")[:300]
        raise RuntimeError(f"API de IA respondeu {e.code}: {detalhe}") from e


def _chama_api(fn):
    """Traduz os erros da API de IA em respostas que o aluno entende."""
    try:
        return fn()
    except SemChave:
        return _erro("o segredo da API de IA ainda está vazio: rode  qc chave", 503,
                     segredo=SECRET_NAME)
    except RuntimeError as e:
        return _erro(str(e), 502)


# ---------------------------------------------------------------- rotas

@app.get("/health")
@app.get("/")
def health():
    return {
        "status": "ok",
        "service": "qc-cognitivo",
        "rotas": ["/falar", "/transcrever", "/analisar-reviews",
                  "/ler-documento", "/analisar-imagem"],
        "gatilho": f"s3://{DATA_BUCKET}/reviews-fotos/ → moderação",
    }


# ---- Lab 2 · voz pela API de IA da QC

@app.post("/falar")
def falar():
    """Texto → fala. A API devolve o MP3 em base64; a função guarda no S3."""
    corpo = app.current_event.json_body or {}
    texto = (corpo.get("texto") or "").strip()
    if not texto:
        return _erro("campo 'texto' vazio", 400)
    voz = corpo.get("voz", "Camila")

    def _faz():
        inicio = time.time()
        r = _api_ia("/tts", {"texto": texto, "voz": voz})
        audio = base64.b64decode(r["audio_b64"])
        chave = f"audios/fala-{uuid.uuid4().hex[:6]}.mp3"
        s3.put_object(Bucket=DATA_BUCKET, Key=chave, Body=audio, ContentType="audio/mpeg")
        link = s3.generate_presigned_url("get_object", Params={"Bucket": DATA_BUCKET, "Key": chave},
                                         ExpiresIn=3600)
        return {"arquivo": chave.split("/", 1)[1], "voz": voz, "bytes": len(audio),
                "segundos": round(time.time() - inicio, 1), "ouvir": link}
    return _chama_api(_faz)


@app.post("/transcrever")
def transcrever():
    """Fala → texto. Lê o áudio do S3 e manda os bytes para a API de IA."""
    q = app.current_event
    arquivo = q.get_query_string_value("arquivo", "")
    idioma = q.get_query_string_value("idioma", "pt-BR")
    if not arquivo:
        return _erro("informe ?arquivo=  (um arquivo de audios/ no bucket)", 400)
    formato = arquivo.rsplit(".", 1)[-1].lower()  # o formato vem da extensão

    def _faz():
        try:
            audio = s3.get_object(Bucket=DATA_BUCKET, Key=f"audios/{arquivo}")["Body"].read()
        except s3.exceptions.NoSuchKey:
            return _erro(f"audios/{arquivo} não existe no bucket", 404)
        if len(audio) > 4_000_000:  # base64 cresce 1/3; o limite do caminho é 6 MB
            return _erro("áudio maior que 4 MB: use um trecho mais curto", 413)
        inicio = time.time()
        r = _api_ia("/stt", {"audio_b64": base64.b64encode(audio).decode(),
                             "formato": formato, "idioma": idioma})
        return {**r, "arquivo": arquivo, "segundos_total": round(time.time() - inicio, 1)}
    return _chama_api(_faz)


# ---- Lab 3 · sentimento (API de IA) e documento (Textract)

def _pendentes(tabela, limite: int) -> list[dict]:
    """Reviews ainda sem sentimento. Scan com filtro: ok para dezenas de itens.

    Em escala, o Scan lê (e cobra) a tabela inteira a cada chamada. Em produção,
    um gatilho do DynamoDB Streams analisaria cada review ao ser gravada.
    """
    itens, kwargs = [], {"FilterExpression": "attribute_not_exists(sentimento)"}
    while len(itens) < limite:
        pagina = tabela.scan(**kwargs)
        itens.extend(pagina["Items"])
        if "LastEvaluatedKey" not in pagina:
            break
        kwargs["ExclusiveStartKey"] = pagina["LastEvaluatedKey"]
    return itens[:limite]


@app.post("/analisar-reviews")
def analisar_reviews():
    """Sentimento + entidades das reviews pendentes, gravados de volta no DynamoDB."""
    limite = min(int(app.current_event.get_query_string_value("limit", "10")), 25)
    tabela = dynamodb.Table(REVIEWS_TABLE)
    itens = _pendentes(tabela, limite)  # o filtro evita pagar duas vezes pela mesma review
    if not itens:
        return {"msg": "Nenhuma review nova para analisar. Todas já processadas."}

    def _faz():
        # Uma chamada só para até 25 textos: a API usa o batch do Comprehend
        r = _api_ia("/sentimento", {"textos": [i["texto"] for i in itens], "idioma": "pt"})
        contagem = {}
        for res in r["resultados"]:
            item = itens[res["indice"]]
            tabela.update_item(
                Key={"produto": item["produto"], "id": item["id"]},
                UpdateExpression="SET sentimento = :s, sentimento_score = :sc, entidades = :e",
                ExpressionAttributeValues={
                    ":s": res["sentimento"],
                    ":sc": {k: _dec(v) for k, v in res["scores"].items()},
                    ":e": [{"text": e["texto"], "type": e["tipo"]} for e in res["entidades"]],
                },
            )
            contagem[res["sentimento"]] = contagem.get(res["sentimento"], 0) + 1
        return {"total_analisadas": len(r["resultados"]), "por_sentimento": contagem}
    return _chama_api(_faz)


@app.post("/ler-documento")
def ler_documento():
    """Textract na mesma imagem, de dois jeitos: OCR puro e campos de formulário.

    detect_document_text devolve linhas soltas, sem saber o que é o quê.
    analyze_document com FORMS devolve pares chave → valor ("Pedido:" → "QC-48213"),
    em português. (Queries e notas/recibos do Textract são só em inglês.)
    """
    arquivo = app.current_event.get_query_string_value("arquivo", "etiqueta.png")
    doc = {"S3Object": {"Bucket": DATA_BUCKET, "Name": f"documentos/{arquivo}"}}
    try:
        ocr = textract.detect_document_text(Document=doc)
        linhas = [b["Text"] for b in ocr["Blocks"] if b["BlockType"] == "LINE"]

        forms = textract.analyze_document(Document=doc, FeatureTypes=["FORMS"])
        campos = _pares_chave_valor(forms["Blocks"])
    except textract.exceptions.InvalidS3ObjectException:
        return _erro(f"documentos/{arquivo} não existe no bucket", 404)
    return {"arquivo": arquivo, "ocr_linhas": linhas, "campos": campos,
            "custo_aprox_usd": {"ocr": 0.0015, "forms": 0.05}}


def _pares_chave_valor(blocos: list[dict]) -> list[dict]:
    """Monta "chave → valor" a partir dos blocos KEY_VALUE_SET do Textract."""
    por_id = {b["Id"]: b for b in blocos}

    def texto(bloco):
        palavras = []
        for rel in bloco.get("Relationships", []):
            if rel["Type"] == "CHILD":
                palavras += [por_id[i].get("Text", "") for i in rel["Ids"]
                             if por_id[i]["BlockType"] == "WORD"]
        return " ".join(palavras)

    pares = []
    for b in blocos:
        if b["BlockType"] == "KEY_VALUE_SET" and "KEY" in b.get("EntityTypes", []):
            valor = ""
            for rel in b.get("Relationships", []):
                if rel["Type"] == "VALUE":
                    valor = " ".join(texto(por_id[i]) for i in rel["Ids"])
            pares.append({"campo": texto(b).rstrip(":"), "valor": valor,
                          "confianca": round(b["Confidence"], 1)})
    return pares


# ---- Lab 4 · catálogo (Rekognition, chamada direta)

@app.post("/analisar-imagem")
def analisar_imagem():
    """Rótulos e texto da foto do produto, gravados como tags no catálogo."""
    q = app.current_event
    arquivo = q.get_query_string_value("arquivo", "produto.jpg")
    produto = q.get_query_string_value("produto", arquivo.rsplit(".", 1)[0])
    img = {"S3Object": {"Bucket": DATA_BUCKET, "Name": f"imagens/{arquivo}"}}
    try:
        rotulos = rekognition.detect_labels(Image=img, MaxLabels=10, MinConfidence=70)["Labels"]
        textos = rekognition.detect_text(Image=img)["TextDetections"]
    except rekognition.exceptions.InvalidS3ObjectException:
        return _erro(f"imagens/{arquivo} não existe no bucket", 404)

    tags = [{"tag": r["Name"], "confianca": round(r["Confidence"], 1)} for r in rotulos]
    texto = " ".join(t["DetectedText"] for t in textos if t["Type"] == "LINE")
    dynamodb.Table(PRODUTOS_TABLE).put_item(Item={
        "produto": produto, "imagem": f"imagens/{arquivo}",
        "tags": [t["tag"] for t in tags], "texto_na_imagem": texto[:500],
        "origem": "rekognition",
    })
    return {"produto": produto, "tags": tags, "texto_na_imagem": texto,
            "gravado_em": PRODUTOS_TABLE}


# ------------------------------------- Lab 4 · moderação (evento do S3)

# Categorias de primeiro nível que mandam a foto para revisão humana.
# É uma decisão de negócio: uma loja de moda praia não bloquearia "Swimwear or Underwear".
BLOQUEIA = {"Explicit Nudity", "Explicit", "Non-Explicit Nudity of Intimate parts and Kissing",
            "Swimwear or Underwear", "Suggestive", "Violence", "Visually Disturbing",
            "Drugs & Tobacco", "Alcohol", "Rude Gestures", "Gambling", "Hate Symbols"}


def moderar(registro: dict) -> dict:
    """Foto anexada a uma review: publica ou manda para revisão."""
    chave = urllib.parse.unquote_plus(registro["s3"]["object"]["key"])  # reviews-fotos/r004.jpg
    review_id = chave.split("/")[-1].rsplit(".", 1)[0]

    rotulos = rekognition.detect_moderation_labels(
        Image={"S3Object": {"Bucket": DATA_BUCKET, "Name": chave}}, MinConfidence=60,
    )["ModerationLabels"]
    # A taxonomia tem até 3 níveis; ParentName aponta só para o nível de cima.
    # Sobe até a raiz para comparar com as categorias de primeiro nível.
    pai = {r["Name"]: r.get("ParentName", "") for r in rotulos}

    def raiz(nome):
        while pai.get(nome):
            nome = pai[nome]
        return nome

    achados = [{"rotulo": r["Name"], "categoria": raiz(r["Name"]),
                "confianca": round(r["Confidence"], 1)} for r in rotulos]
    motivos = sorted({a["categoria"] for a in achados if a["categoria"] in BLOQUEIA})
    status = "em_revisao" if motivos else "publicada"

    # Achar a review pelo id: Scan, porque a chave da tabela é produto + id.
    # Com milhões de reviews, um índice secundário (GSI) por id resolveria.
    tabela = dynamodb.Table(REVIEWS_TABLE)
    itens = tabela.scan(FilterExpression="id = :i",
                        ExpressionAttributeValues={":i": review_id})["Items"]
    if itens:
        tabela.update_item(
            Key={"produto": itens[0]["produto"], "id": review_id},
            UpdateExpression="SET foto = :f, foto_status = :s, foto_motivos = :m",
            ExpressionAttributeValues={":f": chave, ":s": status, ":m": motivos},
        )
    logger.info("moderação", extra={"review": review_id, "status": status,
                                     "rotulos": achados, "review_encontrada": bool(itens)})
    return {"review": review_id, "status": status, "motivos": motivos}


# --------------------------------------------------------- entrada

@logger.inject_lambda_context
def lambda_handler(event, context):
    # Evento do S3 (upload em reviews-fotos/) ou requisição HTTP da Function URL
    if "Records" in event and event["Records"][0].get("eventSource") == "aws:s3":
        return [moderar(r) for r in event["Records"]]
    return app.resolve(event, context)
