"""A fila: máquina de estados explícita, com a transição proibida escrita em código."""

import pytest

from api.erros import TransicaoInvalida, TransicaoProibida


def teste_item_nasce_recebido(fila):
    item = fila.criar("nota-001.txt", "Valor: R$ 10,00")
    assert item["estado"] == "recebido" and item["id"] == "d-0001"
    assert fila.proximo()["id"] == "d-0001"


def teste_duplicado_e_sinalizado_pelo_hash(fila):
    a = fila.criar("nota-001.txt", "mesmo conteúdo")
    fila.mover(a["id"], "extraido", por="deva")
    b = fila.criar("nota-001-reenvio.txt", "mesmo conteúdo")
    assert fila.obter(b["id"])["possivel_duplicado_de"] == a["id"]


def teste_agente_nao_tira_item_da_excecao(fila):
    item = fila.criar("nota-002.txt", "x")
    fila.mover(item["id"], "excecao", por="deva", motivo="acima da alçada", tipo_excecao="alcada")
    with pytest.raises(TransicaoProibida):
        fila.mover(item["id"], "liberado", por="deva")


def teste_auditor_resolve_a_excecao(fila):
    item = fila.criar("nota-002.txt", "x")
    fila.mover(item["id"], "excecao", por="deva", tipo_excecao="alcada")
    r = fila.resolver(item["id"], "liberar", "Carla", "viagem aprovada pela diretoria")
    assert r["estado"] == "liberado" and r["historico"][-1]["por"] == "Carla"


def teste_estado_final_nao_se_reabre(fila):
    item = fila.criar("nota-001.txt", "x")
    fila.mover(item["id"], "extraido", por="deva")
    with pytest.raises(TransicaoInvalida):
        fila.mover(item["id"], "excecao", por="deva")


def teste_painel_mede_a_taxa_de_devolucao_e_incidente(fila):
    a, b = fila.criar("a.txt", "a"), fila.criar("b.txt", "b")
    fila.mover(a["id"], "extraido", por="deva")
    fila.mover(b["id"], "excecao", por="deva", motivo="injeção", tipo_excecao="seguranca")
    painel = fila.painel()
    assert painel["taxa_de_devolucao"] == 0.5 and painel["alerta"] is True
    assert fila.incidentes()[0]["item"] == b["id"]
