"""
Aula 2 / Lab 3B — O desafio da busca: a mesma pergunta por PALAVRA e pelo SENTIDO.

É o que está por trás de `qc busca "texto"`. Mostra lado a lado:
1. a busca por palavra (ILIKE na frase inteira, como uma caixa de busca simples);
2. a busca pelo sentido (pgvector: os 3 produtos com o embedding mais próximo).

O grupo escreve perguntas como um cliente faria e anota onde cada busca acerta
e onde erra. Rode antes `qc indexa` (cria a tabela produtos_vetor).

Uso:
    python buscar_produtos.py "algo para trabalhar em pé"

Variável de ambiente:
    SECRET_ID — segredo com a connection string (o `source qc.sh` exporta)
"""

import os
import sys

import boto3
import psycopg
from fastembed import TextEmbedding
from pgvector.psycopg import register_vector

MODELO = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
# O $HOME do CloudShell tem só 1 GB: o modelo (~220 MB) fica no /tmp
CACHE_MODELO = os.environ.get("FASTEMBED_CACHE", "/tmp/fastembed")


def connection_string():
    secret_id = os.environ.get("SECRET_ID") or sys.exit(
        "SECRET_ID vazio. Rode: source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh")
    return boto3.client("secretsmanager").get_secret_value(SecretId=secret_id)["SecretString"]


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        sys.exit('Uso: qc busca "algo para trabalhar em pé"')
    pergunta = sys.argv[1].strip()

    with psycopg.connect(connection_string(), connect_timeout=15) as conn:
        # Checa a tabela ANTES de carregar o modelo (na 1ª vez ele baixa ~220 MB)
        existe = conn.execute("SELECT to_regclass('produtos_vetor')").fetchone()[0]
        if not existe:
            sys.exit("A tabela produtos_vetor não existe. Rode antes: qc indexa")
        register_vector(conn)

        modelo = TextEmbedding(model_name=MODELO, cache_dir=CACHE_MODELO)
        vetor = next(modelo.embed([pergunta]))

        print(f'\nPergunta: "{pergunta}"\n')

        print("1. Busca por PALAVRA (a frase inteira no nome ou na descrição)")
        achou = conn.execute(
            "SELECT nome FROM produtos_vetor WHERE nome ILIKE %s OR descricao ILIKE %s ORDER BY id",
            (f"%{pergunta}%", f"%{pergunta}%"),
        ).fetchall()
        if achou:
            for (nome,) in achou:
                print(f"   {nome}")
        else:
            print("   (nenhum resultado: nenhum produto tem essa frase escrita)")

        print("\n2. Busca pelo SENTIDO (pgvector, os 3 mais próximos)")
        for nome, preco, dist in conn.execute(
            "SELECT nome, preco, embedding <=> %s AS distancia "
            "FROM produtos_vetor ORDER BY distancia LIMIT 3",
            (vetor,),
        ):
            print(f"   similaridade {1 - dist:.2f}  ·  R$ {preco:>8}  ·  {nome}")

    print("\nAnote: a busca por palavra achou? A pelo sentido acertou? Algum resultado é parecido mas errado?")


if __name__ == "__main__":
    main()
