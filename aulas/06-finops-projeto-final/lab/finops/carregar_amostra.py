"""Aula 6 · Lab 3 — carrega o log de amostra da Eva no CloudWatch Logs.

Cria o log group /eva/turnos (retenção 7 dias, tag projeto=eva) e envia
eva-amostra.jsonl: ~200 chamadas ao modelo, ~125 turnos, medidas pela Eva do
professor (Aula 5, 03-agente-Eva-aws). Cada linha vira um evento JSON — o MESMO
formato que a telemetria.py da Eva escreve no stdout do ECS.

Os preços NÃO vêm no arquivo: o custo_estimado_usd é calculado na hora, com os
valores que VOCÊ informar (EVA_PRECO_ENTRADA_POR_1M / EVA_PRECO_SAIDA_POR_1M).
Sem preço, o custo sai zero — de propósito: número inventado em painel de custo
é pior que painel nenhum.

Dois modos:
  normal    os horários originais (~26 h de uso) são deslocados para terminar agora;
  --rajada  as mesmas chamadas comprimidas nos últimos 10 minutos — é o agente em
            laço. Use depois de criar o filtro de métrica e o alarme (Passo 6): a
            soma de tokens de saída da hora passa do limite e o alarme dispara.

Regras do PutLogEvents que este script respeita (e que derrubavam a versão antiga):
  · eventos em ordem cronológica;
  · nada com mais de 14 dias, nem mais de 2 h no futuro;
  · um lote NÃO pode cobrir mais de 24 h entre o primeiro e o último evento.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

AQUI = Path(__file__).resolve().parent
JANELA_MAX_MS = 23 * 3600 * 1000   # margem de 1 h abaixo do limite de 24 h
EVENTOS_POR_LOTE = 500             # bem abaixo dos 10.000 eventos e 1 MB por lote
RAJADA_S = 600                     # --rajada: tudo nos últimos 10 minutos


def ler_amostra(caminho: Path) -> list[dict]:
    with open(caminho, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def montar_eventos(linhas: list[dict], agora_ms: int, p_in: float, p_out: float,
                   rajada: bool = False) -> list[dict]:
    """Converte as linhas em eventos do CloudWatch, terminando em agora_ms."""
    offsets = [l["offset_s"] for l in linhas]
    ini, fim = min(offsets), max(offsets)
    escala = RAJADA_S / (fim - ini) if rajada and fim > ini else 1.0
    eventos = []
    for original in linhas:
        l = dict(original)
        ts = agora_ms - int((fim - l.pop("offset_s")) * escala * 1000)
        l["custo_estimado_usd"] = round(l["tokens_entrada"] / 1e6 * p_in
                                        + l["tokens_saida"] / 1e6 * p_out, 8)
        l["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts / 1000))
        eventos.append({"timestamp": ts, "message": json.dumps(l, ensure_ascii=False)})
    eventos.sort(key=lambda e: e["timestamp"])
    return eventos


def em_lotes(eventos: list[dict], janela_ms: int = JANELA_MAX_MS,
             maximo: int = EVENTOS_POR_LOTE) -> list[list[dict]]:
    """Fatia eventos ORDENADOS em lotes que respeitam a janela e o tamanho máximo."""
    lotes: list[list[dict]] = []
    for e in eventos:
        if (not lotes or len(lotes[-1]) >= maximo
                or e["timestamp"] - lotes[-1][0]["timestamp"] > janela_ms):
            lotes.append([])
        lotes[-1].append(e)
    return lotes


def carregar(logs, eventos: list[dict], grupo: str, stream: str) -> int:
    try:
        logs.create_log_group(logGroupName=grupo, tags={"projeto": "eva", "aula": "6"})
        print(f"✓ Log group {grupo} criado")
    except logs.exceptions.ResourceAlreadyExistsException:
        print(f"· Log group {grupo} já existe — os eventos vão para um stream novo")
    logs.put_retention_policy(logGroupName=grupo, retentionInDays=7)
    logs.create_log_stream(logGroupName=grupo, logStreamName=stream)
    lotes = em_lotes(eventos)
    for lote in lotes:
        logs.put_log_events(logGroupName=grupo, logStreamName=stream, logEvents=lote)
    return len(lotes)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rajada", action="store_true",
                    help="comprime as chamadas nos últimos 10 min (simula o agente em laço)")
    args = ap.parse_args(argv)

    import boto3

    grupo = os.environ.get("LOG_GROUP", "/eva/turnos")
    regiao = os.environ.get("AWS_REGION", "us-east-1")
    p_in = float(os.environ.get("EVA_PRECO_ENTRADA_POR_1M", "0") or 0)
    p_out = float(os.environ.get("EVA_PRECO_SAIDA_POR_1M", "0") or 0)
    amostra = Path(os.environ.get("AMOSTRA", AQUI / "eva-amostra.jsonl"))

    linhas = ler_amostra(amostra)
    agora_ms = int(time.time() * 1000) - 60_000  # um minuto atrás: nada no "futuro"
    eventos = montar_eventos(linhas, agora_ms, p_in, p_out, rajada=args.rajada)
    stream = f"{'rajada' if args.rajada else 'amostra'}-{time.strftime('%Y%m%d-%H%M%S')}"
    n_lotes = carregar(boto3.client("logs", region_name=regiao), eventos, grupo, stream)

    msgs = [json.loads(e["message"]) for e in eventos]
    turnos = len({m["turno_id"] for m in msgs})
    custo = sum(m["custo_estimado_usd"] for m in msgs)
    saida = sum(m["tokens_saida"] for m in msgs)
    print(f"✓ {len(eventos)} chamadas · {turnos} turnos · {n_lotes} lote(s) → {grupo} / {stream}")
    print(f"  Preços: entrada {p_in} · saída {p_out} USD/1M  →  custo total estimado US$ {custo:.6f}")
    if args.rajada:
        print(f"  Rajada: {saida} tokens de saída em 10 minutos — o alarme do Passo 6 deve disparar.")
    if not (p_in or p_out):
        print("  ⚠️  Preços em 0: o custo vai sair zerado. Exporte EVA_PRECO_* e rode de novo.")
    print("\nPróximo passo: CloudWatch → Logs Insights → log group", grupo)
    return 0


if __name__ == "__main__":
    sys.exit(main())
