"""
Aula 2 / Lab 3B — Busca vetorial dos produtos da QC com pgvector no RDS PostgreSQL.

Passos:
1. Cria a extensão vector, a tabela produtos_vetor e um índice HNSW.
2. Baixa catalogo/produtos.csv do S3.
3. Gera embeddings (MiniLM multilíngue, 384 dimensões) AQUI no CloudShell
   e grava cada produto já com o seu vetor.

A busca em si fica no buscar_produtos.py (`qc busca "texto"`), que mostra a
mesma pergunta por palavra e pelo sentido, lado a lado.

Por que os embeddings são gerados no CloudShell: o Learner Lab não libera o
Amazon Bedrock. Em produção, o mesmo papel seria de um modelo de embedding
no Bedrock (ou do Bedrock Knowledge Bases, que faz o RAG inteiro).

Como rodar: `qc indexa` (o comando instala as dependências no venv).

Variáveis de ambiente (o `source qc.sh` exporta):
    SECRET_ID    — segredo com a connection string
    BUCKET_NAME  — bucket com catalogo/produtos.csv
    (alternativa ao SECRET_ID: DB_HOST + DB_PASSWORD)
"""

import csv
import os
import sys

import boto3
import psycopg
from fastembed import TextEmbedding
from pgvector.psycopg import register_vector

MODELO = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
DIMENSOES = 384
# O $HOME do CloudShell tem só 1 GB: o modelo (~220 MB) fica no /tmp
CACHE_MODELO = os.environ.get("FASTEMBED_CACHE", "/tmp/fastembed")


def connection_string():
    if os.environ.get("SECRET_ID"):
        sm = boto3.client("secretsmanager")
        return sm.get_secret_value(SecretId=os.environ["SECRET_ID"])["SecretString"]
    host, senha = os.environ.get("DB_HOST"), os.environ.get("DB_PASSWORD")
    if host and senha:
        return f"postgresql://qcadmin:{senha}@{host}:5432/qcdb?sslmode=require"
    sys.exit("Exporte SECRET_ID (ou DB_HOST + DB_PASSWORD) — veja o guia.")


def main():
    bucket = os.environ.get("BUCKET_NAME") or sys.exit("Exporte BUCKET_NAME — veja o guia.")

    # 1. Produtos do S3
    print(f"→ Baixando s3://{bucket}/catalogo/produtos.csv...")
    corpo = boto3.client("s3").get_object(Bucket=bucket, Key="catalogo/produtos.csv")["Body"]
    rows = list(csv.DictReader(corpo.read().decode("utf-8").splitlines()))
    print(f"✓ {len(rows)} produtos lidos")

    # 2. Modelo de embedding (baixa na 1ª vez, ~1 min)
    print(f"→ Carregando o modelo {MODELO} (cache em {CACHE_MODELO})...")
    modelo = TextEmbedding(model_name=MODELO, cache_dir=CACHE_MODELO)
    textos = [f"{r['nome']}. {r['descricao']}. Categoria: {r['categoria']}" for r in rows]
    vetores = list(modelo.embed(textos))
    print(f"✓ {len(vetores)} embeddings gerados ({len(vetores[0])} dimensões)")

    with psycopg.connect(connection_string(), connect_timeout=15, autocommit=True) as conn:
        # 3. Extensão + tabela + índice HNSW (distância de cosseno)
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        register_vector(conn)
        conn.execute("DROP TABLE IF EXISTS produtos_vetor")
        conn.execute(
            f"""
            CREATE TABLE produtos_vetor (
                id         INTEGER PRIMARY KEY,
                nome       TEXT NOT NULL,
                descricao  TEXT,
                categoria  TEXT,
                preco      NUMERIC(10,2),
                estoque    INTEGER,
                embedding  vector({DIMENSOES})
            )
            """
        )
        conn.execute(
            "CREATE INDEX produtos_vetor_hnsw ON produtos_vetor "
            "USING hnsw (embedding vector_cosine_ops)"
        )
        print("✓ Tabela produtos_vetor + índice HNSW criados")

        # 4. Gravar cada produto JÁ com o seu vetor
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO produtos_vetor VALUES (%s, %s, %s, %s, %s, %s, %s)",
                [
                    (int(r["id"]), r["nome"], r["descricao"], r["categoria"],
                     float(r["preco"]), int(r["estoque"]), v)
                    for r, v in zip(rows, vetores)
                ],
            )
        print(f"✓ {len(rows)} produtos indexados")

    print('\n✓ Pronto. Agora o desafio: qc busca "algo para trabalhar em pé"')


if __name__ == "__main__":
    main()
