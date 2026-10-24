"""Lab 3: o carregador respeita as regras do PutLogEvents — sem AWS, com um cliente falso.

Regressão: a versão antiga mandava os 198 eventos (que cobrem ~25,6 h) num lote só,
e a AWS recusa lote com mais de 24 h entre o primeiro e o último evento.
"""

import json
import sys
import time
import types
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "finops"))
import carregar_amostra as ca  # noqa: E402

AMOSTRA = ca.ler_amostra(ca.AQUI / "eva-amostra.jsonl")
LIMITE_ALARME = 15_000  # o --threshold do put-metric-alarm do guia (Passo 6)


class _JaExiste(Exception):
    pass


class LogsFalso:
    """Aplica as regras documentadas do PutLogEvents (e falha como a AWS falharia)."""

    exceptions = types.SimpleNamespace(ResourceAlreadyExistsException=_JaExiste)

    def __init__(self):
        self.lotes = []

    def create_log_group(self, **_): pass
    def put_retention_policy(self, **_): pass
    def create_log_stream(self, **_): pass

    def put_log_events(self, logEvents, **_):
        ts = [e["timestamp"] for e in logEvents]
        agora = time.time() * 1000
        assert 1 <= len(ts) <= 10_000
        assert ts == sorted(ts), "eventos fora de ordem"
        assert all(agora - 14 * 86400e3 <= t <= agora + 2 * 3600e3 for t in ts)
        if max(ts) - min(ts) > 24 * 3600e3:
            raise RuntimeError("InvalidParameterException: lote cobre mais de 24 h")
        self.lotes.append(logEvents)


def _eventos(rajada=False, p_in=0.06, p_out=0.24):
    return ca.montar_eventos(AMOSTRA, int(time.time() * 1000) - 60_000, p_in, p_out, rajada)


def teste_a_amostra_cobre_mais_de_24h():
    ev = _eventos()
    assert ev[-1]["timestamp"] - ev[0]["timestamp"] > 24 * 3600e3  # por isso o lote único quebrava


def teste_carrega_tudo_sem_estourar_a_janela_de_24h():
    logs = LogsFalso()
    ev = _eventos()
    n = ca.carregar(logs, ev, "/eva/turnos", "s")
    assert n >= 2 and sum(len(l) for l in logs.lotes) == len(AMOSTRA)


def teste_lote_respeita_o_maximo_de_eventos():
    ev = [{"timestamp": i, "message": "x"} for i in range(1200)]
    assert [len(l) for l in ca.em_lotes(ev)] == [500, 500, 200]


def teste_sem_preco_o_custo_sai_zero():
    assert all(json.loads(e["message"])["custo_estimado_usd"] == 0 for e in _eventos(p_in=0, p_out=0))


def teste_custo_por_turno_com_o_preco_do_nova_lite():
    turnos = {}
    for e in _eventos():
        m = json.loads(e["message"])
        turnos[m["turno_id"]] = turnos.get(m["turno_id"], 0) + m["custo_estimado_usd"]
    assert len(turnos) == 126
    assert sum(turnos.values()) / len(turnos) == pytest.approx(0.000305, rel=0.01)


def teste_rajada_cabe_em_10_min_e_faz_o_alarme_disparar():
    logs = LogsFalso()
    ev = _eventos(rajada=True)
    assert ev[-1]["timestamp"] - ev[0]["timestamp"] <= ca.RAJADA_S * 1000
    assert ca.carregar(logs, ev, "/eva/turnos", "r") == 1
    saida = sum(json.loads(e["message"])["tokens_saida"] for e in ev)
    # a rajada pode cair na virada da hora e se dividir entre dois períodos do alarme
    assert saida / 2 > LIMITE_ALARME


def teste_modo_normal_nao_faz_o_alarme_disparar():
    hora = {}
    for e in _eventos():
        h = e["timestamp"] // 3_600_000
        hora[h] = hora.get(h, 0) + json.loads(e["message"])["tokens_saida"]
    assert max(hora.values()) < LIMITE_ALARME  # uso normal: o alarme fica quieto
