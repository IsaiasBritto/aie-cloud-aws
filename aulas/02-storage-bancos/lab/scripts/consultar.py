"""
Aula 2 / Lab 2 — Roda uma consulta SQL no PostgreSQL do RDS e mostra o resultado.

É o que está por trás de `qc sql "SELECT ..."`. A connection string vem do
Secrets Manager na hora: a senha não aparece na tela nem fica numa variável.

Uso:
    python consultar.py "SELECT nome, preco FROM t_produtos ORDER BY preco DESC LIMIT 5"

Variável de ambiente:
    SECRET_ID — segredo com a connection string (o `source qc.sh` exporta)
"""

import os
import sys

import boto3
import psycopg


def connection_string():
    secret_id = os.environ.get("SECRET_ID") or sys.exit(
        "SECRET_ID vazio. Rode: source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh")
    sm = boto3.client("secretsmanager")
    return sm.get_secret_value(SecretId=secret_id)["SecretString"]


def tabela(colunas, linhas):
    """Imprime as linhas alinhadas em colunas, como o psql."""
    texto = [[("" if v is None else str(v)) for v in linha] for linha in linhas]
    larguras = [max([len(c)] + [len(l[i]) for l in texto]) for i, c in enumerate(colunas)]
    print(" | ".join(c.ljust(w) for c, w in zip(colunas, larguras)))
    print("-+-".join("-" * w for w in larguras))
    for l in texto:
        print(" | ".join(v.ljust(w) for v, w in zip(l, larguras)))
    print(f"({len(linhas)} linha{'s' if len(linhas) != 1 else ''})")


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        sys.exit('Uso: qc sql "SELECT * FROM t_produtos LIMIT 5"')
    sql = sys.argv[1]
    try:
        with psycopg.connect(connection_string(), connect_timeout=15, autocommit=True) as conn:
            cur = conn.execute(sql)
            if cur.description:
                tabela([d.name for d in cur.description], cur.fetchall())
            else:
                print(f"OK ({cur.rowcount} linha(s) afetada(s))")
    except psycopg.OperationalError as e:
        sys.exit(f"Não conectei no RDS: {e}\nO IP do CloudShell mudou? Rode o source do qc.sh: ele mostra o apply que libera o IP novo.")
    except psycopg.Error as e:
        sys.exit(f"Erro no SQL: {e}")


if __name__ == "__main__":
    main()
