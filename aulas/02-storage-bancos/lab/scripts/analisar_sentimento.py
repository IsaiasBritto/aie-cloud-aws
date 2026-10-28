"""
Aula 2 / Bloco 3 — Demo do professor: sentimento das reviews, regra ou IA?

É o que está por trás de `qc sentimento`. Lê as reviews do DynamoDB que ainda
não têm sentimento, classifica e grava o resultado de volta em cada item:

- Com o Amazon Comprehend liberado (a conta AWS do professor): sentimento,
  score por classe e entidades vêm do Comprehend.
- Sem Comprehend (o Learner Lab nega o serviço, até para a LabRole): cai numa
  classificação por palavras-chave, SEM IA.

Cada item ganha o campo `fonte` ("comprehend" ou "regras-locais"), para
ninguém confundir as duas. A comparação é a discussão da aula: onde a regra
erra, quanto custa esse erro e quanto custa evitá-lo.

Variável de ambiente:
    DYNAMO_TABLE — tabela de reviews (o `source qc.sh` exporta)
"""

import os
import re
import sys
from collections import Counter
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

# ------------------------------------------------------------- regras (sem IA)
# Lista curta, feita para as frases do popular_reviews.py. Uma regra não
# entende contexto nem ironia: é exatamente o que o Comprehend resolve.
NEGATIVOS = ["não recomendo", "decepcion", "defeito", "esperava mais", "amassad", "trocar", "ruim", "péssim"]
POSITIVOS = ["adorei", "excelente", "recomendo", "ótimo", "maravilhos", "perfeitamente", "vale a pena",
             "bom", "superou", "compraria", "rápido"]


def por_regras(texto):
    t = texto.lower()
    neg = [p for p in NEGATIVOS if p in t]
    # "não recomendo" não pode contar também como "recomendo"
    t_sem_neg = re.sub("|".join(map(re.escape, neg)), " ", t) if neg else t
    pos = [p for p in POSITIVOS if p in t_sem_neg]
    if pos and neg:
        sentimento = "MIXED"
    elif pos:
        sentimento = "POSITIVE"
    elif neg:
        sentimento = "NEGATIVE"
    else:
        sentimento = "NEUTRAL"
    return {"sentimento": sentimento, "entidades": [], "palavras_chave": pos + neg, "fonte": "regras-locais"}


# ------------------------------------------------------------- Comprehend (com IA)
def por_comprehend(textos):
    """Até 25 textos por chamada (limite do Comprehend)."""
    cp = boto3.client("comprehend")
    sent = {r["Index"]: r for r in cp.batch_detect_sentiment(TextList=textos, LanguageCode="pt")["ResultList"]}
    ent = {r["Index"]: r for r in cp.batch_detect_entities(TextList=textos, LanguageCode="pt")["ResultList"]}
    saida = []
    for i in range(len(textos)):
        s = sent.get(i)
        if s is None:  # foi para a ErrorList (texto vazio, longo demais...)
            saida.append(None)
            continue
        saida.append({
            "sentimento": s["Sentiment"],
            # O DynamoDB não aceita float: número decimal vai como Decimal
            "sentimento_score": {k.lower(): Decimal(str(round(v, 3))) for k, v in s["SentimentScore"].items()},
            "entidades": [{"texto": e["Text"], "tipo": e["Type"], "score": Decimal(str(round(e["Score"], 3)))}
                          for e in ent.get(i, {"Entities": []})["Entities"]],
            "fonte": "comprehend",
        })
    return saida


def main():
    nome = os.environ.get("DYNAMO_TABLE") or sys.exit(
        "DYNAMO_TABLE vazio. Rode: source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh")
    tabela = boto3.resource("dynamodb").Table(nome)

    itens, kw = [], {}
    while True:  # 30 itens cabem numa página, mas o laço vale para qualquer tamanho
        pagina = tabela.scan(**kw)
        itens += pagina["Items"]
        if "LastEvaluatedKey" not in pagina:
            break
        kw["ExclusiveStartKey"] = pagina["LastEvaluatedKey"]
    pendentes = [i for i in itens if "sentimento" not in i]
    if not pendentes:
        print("Nenhuma review nova para analisar. Para refazer: qc carga reviews (recria as 30).")
    else:
        print(f"→ {len(pendentes)} reviews para analisar...")
        usou_regras = False
        for ini in range(0, len(pendentes), 25):
            lote = pendentes[ini:ini + 25]
            try:
                resultados = por_comprehend([i["texto"] for i in lote])
            except ClientError as e:
                if e.response["Error"]["Code"] != "AccessDeniedException":
                    raise
                usou_regras = True
                resultados = [por_regras(i["texto"]) for i in lote]
            for item, res in zip(lote, resultados):
                if res is None:
                    continue
                campos = ", ".join(f"#{k} = :{k}" for k in res)
                tabela.update_item(
                    Key={"produto_id": item["produto_id"], "review_id": item["review_id"]},
                    UpdateExpression=f"SET {campos}",
                    ExpressionAttributeNames={f"#{k}": k for k in res},
                    ExpressionAttributeValues={f":{k}": v for k, v in res.items()},
                )
        if usou_regras:
            print("⚠ O Comprehend foi negado nesta conta (Learner Lab): o sentimento veio de REGRAS")
            print("  por palavra-chave, sem IA. Cada item traz fonte = regras-locais.")
        else:
            print("✓ Sentimento e entidades vieram do Amazon Comprehend (fonte = comprehend).")

    itens = tabela.scan()["Items"]
    print("\n=== Sentimento geral ===")
    for k, v in Counter(i.get("sentimento", "SEM ANÁLISE") for i in itens).most_common():
        print(f"  {k:<9} {v}")
    print("\n=== Onde comparar ===")
    print(f"  Console: DynamoDB → Tables → {nome} → Explore table items")
    print(f'  PartiQL: SELECT texto, score, sentimento, fonte FROM "{nome}" WHERE produto_id = 5')


if __name__ == "__main__":
    main()
