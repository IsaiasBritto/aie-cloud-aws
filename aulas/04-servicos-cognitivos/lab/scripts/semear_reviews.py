"""
Semeia 10 reviews de exemplo na tabela DynamoDB da Aula 4.

Uso:  python3 scripts/semear_reviews.py
Variável de ambiente: REVIEWS_TABLE (source exportar-outputs.sh)

Repare no que NÃO existe aqui: senha de banco, host, porta, chave de acesso.
O boto3 grava na tabela com a credencial da sessão do CloudShell (LabRole), e a
autorização é uma policy do IAM (dynamodb:BatchWriteItem no ARN da tabela).
Compare com um banco autogerenciado numa EC2 (exercício 1.3).
"""
import os
import sys

import boto3

TABELA = os.environ.get("REVIEWS_TABLE")
if not TABELA:
    print("Exporte REVIEWS_TABLE com o nome da tabela:")
    print("  source ~/aie-cloud/aulas/04-servicos-cognitivos/lab/exportar-outputs.sh")
    sys.exit(1)

reviews = [
    {"id": "r001", "produto": "Notebook Pro X", "texto": "Excelente laptop, a bateria dura mais de 8 horas e o processador é muito rápido.", "estrelas": 5},
    {"id": "r002", "produto": "Fone Bluetooth QC-50", "texto": "Qualidade de som péssima, muito abaixo do esperado. Totalmente decepcionante.", "estrelas": 1},
    {"id": "r003", "produto": "Teclado Mecânico RGB", "texto": "Digitação muito boa mas o preço é elevado para o que oferece.", "estrelas": 3},
    {"id": "r004", "produto": "Mouse Gamer Quantum", "texto": "Perfeito para jogos, resposta imediata e design confortável. Recomendo!", "estrelas": 5},
    {"id": "r005", "produto": "Monitor 4K 27pol", "texto": "Imagem linda mas veio com um pixel morto. Atendimento resolveu rápido.", "estrelas": 4},
    {"id": "r006", "produto": "Cadeira Ergonômica", "texto": "Horrível, completamente desconfortável após 1 hora de uso. Não recomendo de jeito algum.", "estrelas": 1},
    {"id": "r007", "produto": "HD Externo 2TB", "texto": "Velocidade de transferência ótima, funciona perfeitamente no dia a dia.", "estrelas": 5},
    {"id": "r008", "produto": "Webcam Full HD", "texto": "Qualidade de imagem ok para videoconferências, nada excepcional pelo preço.", "estrelas": 3},
    {"id": "r009", "produto": "Impressora Laser", "texto": "Rápida e econômica em toner. Exatamente o que precisava para o escritório.", "estrelas": 4},
    {"id": "r010", "produto": "Caixa Bluetooth QC-Bass", "texto": "Som cheio e potente. Valeu cada centavo. Já é minha segunda compra.", "estrelas": 5},
]

tabela = boto3.resource("dynamodb").Table(TABELA)

# put_item sobrescreve o item inteiro: rodar de novo "zera" a análise (idempotente)
with tabela.batch_writer() as lote:
    for r in reviews:
        lote.put_item(Item=r)

print(f"✓ {len(reviews)} reviews gravadas em {TABELA}")
print("\nDistribuição de estrelas:")
for stars in range(1, 6):
    count = sum(1 for r in reviews if r["estrelas"] == stars)
    bar = "★" * stars + "☆" * (5 - stars)
    print(f"  {bar}: {count} reviews")
print("\nConfira no console: DynamoDB → Tables → a tabela → Explore table items")
