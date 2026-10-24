"""A fronteira vista por HTTP: 14 operações na API, 5 na mão do agente."""

import json

from api.configuracao import RAIZ
from api.principal import aplicacao

OPERACOES_HUMANAS = {"aprovarProposta", "recusarProposta", "resolverExcecao", "criarItem"}


def _operacoes(spec: dict) -> set[str]:
    return {op["operationId"] for metodos in spec["paths"].values() for op in metodos.values()}


def teste_a_api_tem_14_operacoes():
    assert len(_operacoes(aplicacao.openapi())) == 14


def teste_o_agente_carrega_5_operacoes_e_nenhuma_aprova():
    agente = _operacoes(json.loads((RAIZ / "agente" / "openapi-agente.json").read_text("utf-8")))
    assert len(agente) == 5
    assert agente <= _operacoes(aplicacao.openapi())
    assert not agente & OPERACOES_HUMANAS


def teste_agente_tentando_aprovar_a_propria_proposta_recebe_403(http):
    p = http.post("/memoria/propostas", json={"texto": "voo -> viagem_aerea", "evidencia": "d-0001"}).json()
    sem_cabecalho = http.post(f"/memoria/propostas/{p['id']}/aprovar")
    como_deva = http.post(f"/memoria/propostas/{p['id']}/aprovar", headers={"X-Auditor": "deva"})
    assert sem_cabecalho.status_code == 403 and como_deva.status_code == 403
    assert sem_cabecalho.json()["como_resolver"]


def teste_agente_tentando_liberar_excecao_recebe_409(http):
    item = http.post("/fila", json={"arquivo": "n.txt", "conteudo": "x"}).json()
    http.post(f"/fila/{item['id']}/resultado", json={"estado": "excecao", "motivo": "alçada",
                                                     "tipo_excecao": "alcada"})
    r = http.post(f"/fila/{item['id']}/resultado", json={"estado": "liberado", "motivo": "sei resolver"})
    assert r.status_code == 409 and r.json()["erro"] == "transicao_proibida"
