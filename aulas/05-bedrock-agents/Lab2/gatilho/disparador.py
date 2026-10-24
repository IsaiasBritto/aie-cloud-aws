"""Disparador: o nível 3 da escada — ninguém digitou nada; um arquivo chegou.

Três modos:

    python gatilho/disparador.py --semear
        Local ou CloudShell, sem nuvem: põe as 3 notas de exemplo na fila (POST /fila).

    python gatilho/disparador.py --s3 NOME_DO_BUCKET
        Envia as notas para s3://BUCKET/entrada/. A regra do EventBridge (prefixo
        entrada/) aciona a Lambda, que avisa a fila SQS.

    python gatilho/disparador.py --sqs URL_DA_FILA
        Esvazia a fila SQS: para cada aviso, lê o objeto no S3 e cria o item (POST /fila).
        É a ponte entre o evento na nuvem e o serviço rodando no seu terminal.

Variável: API_URL (padrão http://localhost:8000)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cliente import ClienteApi  # noqa: E402

AMOSTRAS = Path(__file__).resolve().parent / "amostras"


def amostras() -> list[Path]:
    """Ordem da demo: original, reenvio, nota maliciosa (o '-' viria antes do '.')."""
    return sorted(AMOSTRAS.glob("*.txt"), key=lambda a: (a.stem.split("-")[1], "reenvio" in a.stem))


def semear(cliente: ClienteApi) -> list[dict]:
    criados = []
    for arquivo in amostras():
        r = cliente.post("/fila", json={"arquivo": arquivo.name, "origem": "semear",
                                         "conteudo": arquivo.read_text(encoding="utf-8")})
        r.raise_for_status()
        item = r.json()
        criados.append(item)
        print(f"  ✓ {item['id']}  {arquivo.name}  → {item['estado']}")
    return criados


def enviar_para_s3(bucket: str) -> None:
    import boto3

    s3 = boto3.client("s3")
    for arquivo in amostras():
        chave = f"entrada/{arquivo.name}"
        s3.upload_file(str(arquivo), bucket, chave)
        print(f"  ✓ s3://{bucket}/{chave}")
    print("O EventBridge aciona a Lambda em segundos. Depois: --sqs URL_DA_FILA")


def esvaziar_sqs(cliente: ClienteApi, url_fila: str) -> int:
    import boto3

    sqs, s3, total = boto3.client("sqs"), boto3.client("s3"), 0
    while True:
        lote = sqs.receive_message(QueueUrl=url_fila, MaxNumberOfMessages=10, WaitTimeSeconds=2)
        mensagens = lote.get("Messages", [])
        if not mensagens:
            break
        for m in mensagens:
            aviso = json.loads(m["Body"])
            corpo = s3.get_object(Bucket=aviso["bucket"], Key=aviso["chave"])["Body"].read()
            r = cliente.post("/fila", json={"arquivo": aviso["chave"].split("/")[-1], "origem": "s3",
                                             "conteudo": corpo.decode("utf-8")})
            r.raise_for_status()
            print(f"  ✓ {r.json()['id']}  {aviso['chave']}")
            sqs.delete_message(QueueUrl=url_fila, ReceiptHandle=m["ReceiptHandle"])
            total += 1
    print(f"{total} aviso(s) transformado(s) em item da fila.")
    return total


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--semear", action="store_true", help="põe as notas de exemplo na fila")
    g.add_argument("--s3", metavar="BUCKET", help="envia as notas para s3://BUCKET/entrada/")
    g.add_argument("--sqs", metavar="URL", help="esvazia a fila SQS para a API")
    a = p.parse_args()
    if a.semear:
        semear(ClienteApi())
    elif a.s3:
        enviar_para_s3(a.s3)
    else:
        esvaziar_sqs(ClienteApi(), a.sqs)


if __name__ == "__main__":
    main()
