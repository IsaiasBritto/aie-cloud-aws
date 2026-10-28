"""
Aula 2 / Lab 1B — Gera os pedidos sintéticos da QC para o data lake.

É o que está por trás de `qc lake gera`. Escreve um CSV com ~200 mil pedidos de
12 meses (out/2025 a set/2026), usando os 20 produtos de data/produtos.csv.
A semente é fixa: todo aluno gera exatamente o mesmo arquivo, e os números do
`qc lake compara` batem entre os grupos.

Só biblioteca padrão: roda no CloudShell sem instalar nada.

Uso:
    python gerar_pedidos.py /tmp/pedidos.csv [quantidade]
"""

import csv
import datetime
import random
import sys
from pathlib import Path

SEMENTE = 2026
PADRAO = 200_000
INICIO = datetime.date(2025, 10, 1)
DIAS = (datetime.date(2026, 9, 30) - INICIO).days + 1
UFS = ["SP", "RJ", "MG", "RS", "PR", "SC", "BA", "PE", "CE", "GO", "DF", "ES", "PA", "AM"]
PESO_UF = [30, 12, 11, 7, 7, 5, 5, 4, 3, 3, 3, 2, 2, 1]
CANAIS = ["site", "app", "agente"]
PESO_CANAL = [50, 35, 15]
PRODUTOS = Path(__file__).resolve().parents[1] / "data" / "produtos.csv"


def main():
    if len(sys.argv) < 2:
        sys.exit("Uso: python gerar_pedidos.py /tmp/pedidos.csv [quantidade]")
    destino = Path(sys.argv[1])
    total = int(sys.argv[2]) if len(sys.argv) > 2 else PADRAO

    with open(PRODUTOS, encoding="utf-8") as f:
        produtos = [(int(p["id"]), p["categoria"], float(p["preco"])) for p in csv.DictReader(f)]

    rnd = random.Random(SEMENTE)
    with open(destino, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["pedido_id", "data", "cliente_id", "produto_id", "categoria",
                    "uf", "canal", "quantidade", "valor", "mes"])
        for i in range(1, total + 1):
            dia = INICIO + datetime.timedelta(days=rnd.randrange(DIAS))
            pid, cat, preco = rnd.choice(produtos)
            qtd = rnd.choices([1, 2, 3], weights=[80, 15, 5])[0]
            desconto = rnd.choice([1.0, 1.0, 1.0, 0.95, 0.9])
            w.writerow([
                f"P{i:07d}", dia.isoformat(), rnd.randint(1, 50_000), pid, cat,
                rnd.choices(UFS, weights=PESO_UF)[0], rnd.choices(CANAIS, weights=PESO_CANAL)[0],
                qtd, f"{preco * qtd * desconto:.2f}", dia.strftime("%Y-%m"),
            ])

    mb = destino.stat().st_size / 1024 / 1024
    print(f"✓ {total:,} pedidos em {destino} ({mb:.1f} MB)".replace(",", "."))


if __name__ == "__main__":
    main()
