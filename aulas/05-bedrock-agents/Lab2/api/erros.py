"""Erros do Serviço de Continuidade.

Regra do projeto (a mesma do Deva3): todo erro traz **como resolver**.
E aqui o erro também é prompt: o agente lê a mensagem e decide o próximo passo.
"""

from __future__ import annotations


class ErroDoDeva(Exception):
    """Erro base. Tudo que a API lança conscientemente herda daqui."""

    codigo = "erro_interno"
    situacao_http = 500

    def __init__(self, mensagem: str, como_resolver: str | None = None, **extra) -> None:
        super().__init__(mensagem)
        self.mensagem = mensagem
        self.como_resolver = como_resolver
        self.extra = extra

    def como_dicionario(self) -> dict:
        return {"erro": self.codigo, "mensagem": self.mensagem,
                "como_resolver": self.como_resolver, **self.extra}


class NaoEncontrado(ErroDoDeva):
    codigo = "nao_encontrado"
    situacao_http = 404


class SemAuditor(ErroDoDeva):
    """A operação exige um humano identificado — e o agente não é um."""

    codigo = "sem_auditor"
    situacao_http = 403


class TransicaoProibida(ErroDoDeva):
    """A transição existe, mas não para quem pediu. Ex.: o agente tirando item da exceção."""

    codigo = "transicao_proibida"
    situacao_http = 409


class TransicaoInvalida(ErroDoDeva):
    """A transição não existe na máquina de estados."""

    codigo = "transicao_invalida"
    situacao_http = 409


class IncidenteSeguranca(ErroDoDeva):
    """O texto parece instrução de manipulação. Vira incidente, não memória."""

    codigo = "incidente_seguranca"
    situacao_http = 422


class EncaminharControladoria(ErroDoDeva):
    """O texto tenta MUDAR uma alçada ou limite. Quem decide é a Controladoria."""

    codigo = "encaminhar_controladoria"
    situacao_http = 422


class FilaDeAprendizadoCheia(ErroDoDeva):
    """O teto de propostas pendentes foi atingido. Fila que ninguém revisa é dívida."""

    codigo = "fila_de_aprendizado_cheia"
    situacao_http = 429


class PedidoInvalido(ErroDoDeva):
    codigo = "pedido_invalido"
    situacao_http = 422
