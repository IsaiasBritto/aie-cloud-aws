"""O gatilho, o ciclo de ponta a ponta e os três freios — sem rede."""

import ciclo_do_agente as ciclo
import disparador
from lambda_gatilho import deve_disparar


def teste_memory_md_no_bucket_nao_dispara_o_ciclo():
    assert deve_disparar("entrada/nota-001.pdf")
    assert not deve_disparar("memoria/MEMORY.md")
    assert not deve_disparar("entrada/MEMORY.md")
    assert not deve_disparar("saida/parecer.json")


def teste_tres_voltas_extraido_duplicado_excecao_e_a_quarta_nao_faz_nada(cliente):
    disparador.semear(cliente)
    voltas = [ciclo.uma_volta(cliente) for _ in range(4)]
    assert [v.get("estado") for v in voltas[:3]] == ["extraido", "duplicado", "excecao"]
    assert voltas[3] == {"acao": "nada a fazer"}
    assert voltas[0]["proposta"].startswith("p-")       # dúvida virou proposta, não decisão
    assert cliente.get("/incidentes").json()[0]["arquivo"] == "nota-002.txt"
    # o auditor assina; na próxima nota igual, o agente usa a regra assinada
    cliente.post(f"/memoria/propostas/{voltas[0]['proposta']}/aprovar", headers={"X-Auditor": "Ana"})
    cliente.post("/fila", json={"arquivo": "nota-003.txt", "conteudo":
                                "Descrição: Estacionamento no aeroporto de Guarulhos\nValor: R$ 40,00"})
    assert "MEMORY.md" in ciclo.uma_volta(cliente)["motivo"]


class _ModeloQueNaoPara:
    """Finge um modelo que pede ferramenta para sempre — o laço infinito clássico."""

    def __init__(self, tokens_por_volta=100):
        self.n, self.tokens = 0, tokens_por_volta

    def converse(self, **_):
        self.n += 1
        return {"stopReason": "tool_use", "usage": {"inputTokens": self.tokens, "outputTokens": 0},
                "output": {"message": {"role": "assistant", "content": [
                    {"toolUse": {"toolUseId": f"t{self.n}", "name": "proximoItem", "input": {}}}]}}}


def teste_os_freios_param_o_laco(cliente):
    voltas = ciclo.volta_com_bedrock(cliente, _ModeloQueNaoPara(100))
    assert voltas["parou_por"] == "max_voltas" and voltas["voltas"] == ciclo.MAX_VOLTAS
    caro = ciclo.volta_com_bedrock(cliente, _ModeloQueNaoPara(15000))
    assert caro["parou_por"] == "orcamento" and caro["voltas"] == 2
