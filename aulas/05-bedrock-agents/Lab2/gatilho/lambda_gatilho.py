"""Lambda do gatilho: S3 (Object Created) → EventBridge → esta função → SQS.

O filtro de verdade está na REGRA do EventBridge (prefixo entrada/): barrar na
borda custa menos do que acordar a Lambda. Este filtro aqui é a segunda linha:
se alguém mudar a regra, o MEMORY.md gravado no bucket continua sem disparar o
ciclo do agente — senão o agente acordaria a cada linha de memória aprovada.
"""

from __future__ import annotations

import json
import os

PREFIXO = "entrada/"
NUNCA_DISPARAM = {"MEMORY.md", "memoria-pendente.md"}

_sqs = None


def deve_disparar(chave: str) -> bool:
    return chave.startswith(PREFIXO) and chave.split("/")[-1] not in NUNCA_DISPARAM


def lambda_handler(event, context):
    global _sqs
    detalhe = event.get("detail", {})
    bucket = detalhe.get("bucket", {}).get("name")
    chave = detalhe.get("object", {}).get("key", "")
    if not bucket or not deve_disparar(chave):
        print(json.dumps({"ignorado": chave}))
        return {"disparou": False, "chave": chave}

    if _sqs is None:
        import boto3

        _sqs = boto3.client("sqs")
    _sqs.send_message(QueueUrl=os.environ["FILA_URL"],
                      MessageBody=json.dumps({"bucket": bucket, "chave": chave,
                                              "etag": detalhe.get("object", {}).get("etag")}))
    print(json.dumps({"disparou": chave}))
    return {"disparou": True, "chave": chave}
