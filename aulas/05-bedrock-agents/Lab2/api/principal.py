"""Serviço de Continuidade do Deva — a fronteira escrita em código.

A API tem 14 operações. A especificação que o agente carrega
(agente/openapi-agente.json) tem 5 — e nenhuma delas aprova coisa alguma.

    O agente usa (5):            GET  /memoria
                                 POST /memoria/propostas
                                 GET  /fila/proximo
                                 GET  /fila/{id}
                                 POST /fila/{id}/resultado

    Só humanos e o gatilho (9):  GET  /saude · GET /painel · GET /memoria/propostas
                                 POST /memoria/propostas/{id}/aprovar   (X-Auditor)
                                 POST /memoria/propostas/{id}/recusar   (X-Auditor)
                                 POST /fila · GET /fila
                                 POST /fila/{id}/resolver               (X-Auditor)
                                 GET  /incidentes

Instrução é intenção. Permissão é controle. O que você não quer que o agente faça,
você não expõe.

Subir:  uvicorn api.principal:aplicacao --port 8000
"""

from __future__ import annotations

from pathlib import Path
from typing import Literal

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field

from api.configuracao import DIRETORIO_DADOS, NOME_DO_AGENTE, SEMENTE_MEMORIA
from api.erros import ErroDoDeva
from api.servicos.armazenamento import Repositorio
from api.servicos.fila import ServicoFila
from api.servicos.memoria import ServicoMemoria


class NovaProposta(BaseModel):
    texto: str = Field(..., description="A regra que o agente quer aprender, em uma linha.")
    evidencia: str = Field("", description="O item da fila que motivou a proposta.")


class Decisao(BaseModel):
    motivo: str = ""


class NovoItem(BaseModel):
    arquivo: str
    conteudo: str
    origem: str = "manual"


class Resultado(BaseModel):
    estado: Literal["extraido", "duplicado", "excecao", "liberado", "recusado"]
    dados: dict | None = None
    motivo: str = ""
    tipo_excecao: Literal["seguranca", "alcada", "categoria", "leitura", "regra"] | None = None


class Resolucao(BaseModel):
    decisao: Literal["liberar", "recusar"]
    motivo: str = ""


def criar_aplicacao(diretorio: Path | None = None) -> FastAPI:
    repo = Repositorio(diretorio or DIRETORIO_DADOS, SEMENTE_MEMORIA)
    memoria, fila = ServicoMemoria(repo), ServicoFila(repo)

    app = FastAPI(title="Deva · Serviço de Continuidade", version="1.0",
                  description="Memória revisável, fila de exceções e a fronteira em código.")

    @app.exception_handler(ErroDoDeva)
    async def _erro(_: Request, exc: ErroDoDeva) -> JSONResponse:
        return JSONResponse(status_code=exc.situacao_http, content=exc.como_dicionario())

    # ---------------------------------------------------------- 1-2 · operação
    @app.get("/saude", operation_id="saude", tags=["humano"])
    def saude() -> dict:
        return {"estado": "ok", "dados": str(repo.diretorio)}

    @app.get("/painel", operation_id="painel", tags=["humano"])
    def painel() -> dict:
        return {**fila.painel(), "propostas_pendentes": len(memoria.pendentes()),
                "incidentes": len(fila.incidentes())}

    # ---------------------------------------------------------- 3-7 · memória
    @app.get("/memoria", operation_id="lerMemoria", tags=["agente"])
    def ler_memoria() -> dict:
        return memoria.ler()

    @app.get("/memoria/propostas", operation_id="listarPropostas", tags=["humano"])
    def listar_propostas() -> list[dict]:
        return memoria.pendentes()

    @app.post("/memoria/propostas", operation_id="proporMemoria", status_code=201, tags=["agente"])
    def propor_memoria(corpo: NovaProposta) -> dict:
        return memoria.propor(corpo.texto, corpo.evidencia, por=NOME_DO_AGENTE)

    @app.post("/memoria/propostas/{id_proposta}/aprovar", operation_id="aprovarProposta", tags=["humano"])
    def aprovar_proposta(id_proposta: str, x_auditor: str | None = Header(None)) -> dict:
        return memoria.aprovar(id_proposta, x_auditor)

    @app.post("/memoria/propostas/{id_proposta}/recusar", operation_id="recusarProposta", tags=["humano"])
    def recusar_proposta(id_proposta: str, corpo: Decisao | None = None,
                         x_auditor: str | None = Header(None)) -> dict:
        return memoria.recusar(id_proposta, x_auditor, (corpo or Decisao()).motivo)

    # ---------------------------------------------------------- 8-13 · fila
    @app.post("/fila", operation_id="criarItem", status_code=201, tags=["gatilho"])
    def criar_item(corpo: NovoItem) -> dict:
        return fila.criar(corpo.arquivo, corpo.conteudo, corpo.origem)

    @app.get("/fila", operation_id="listarFila", tags=["humano"])
    def listar_fila(estado: str | None = None) -> list[dict]:
        return fila.listar(estado)

    @app.get("/fila/proximo", operation_id="proximoItem", tags=["agente"],
             responses={204: {"description": "Nada a fazer."}})
    def proximo_item():
        item = fila.proximo()
        return item if item else Response(status_code=204)

    @app.get("/fila/{id_item}", operation_id="obterItem", tags=["agente"])
    def obter_item(id_item: str) -> dict:
        return fila.obter(id_item)

    @app.post("/fila/{id_item}/resultado", operation_id="registrarResultado", tags=["agente"])
    def registrar_resultado(id_item: str, corpo: Resultado) -> dict:
        # Esta rota é a do AGENTE: quem chama aqui é sempre 'deva'.
        return fila.mover(id_item, corpo.estado, por=NOME_DO_AGENTE, dados=corpo.dados,
                          motivo=corpo.motivo, tipo_excecao=corpo.tipo_excecao)

    @app.post("/fila/{id_item}/resolver", operation_id="resolverExcecao", tags=["humano"])
    def resolver_excecao(id_item: str, corpo: Resolucao, x_auditor: str | None = Header(None)) -> dict:
        return fila.resolver(id_item, corpo.decisao, x_auditor, corpo.motivo)

    # ---------------------------------------------------------- 14 · segurança
    @app.get("/incidentes", operation_id="listarIncidentes", tags=["humano"])
    def listar_incidentes() -> list[dict]:
        return fila.incidentes()

    return app


aplicacao = criar_aplicacao()
