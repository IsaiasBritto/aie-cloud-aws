"""Fila de documentos com máquina de estados explícita.

    RECEBIDO ──(deva)──> EXTRAIDO        fim
             ──(deva)──> DUPLICADO       fim
             ──(deva)──> EXCECAO ──(auditor)──> LIBERADO | RECUSADO

A transição proibida é código, não recomendação:

    if estado is EXCECAO and por == 'deva':
        raise TransicaoProibida

Exceção não volta para o agente, mesmo que ele ache que sabe resolver.
"""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from enum import Enum

from api.configuracao import ALERTA_DEVOLUCAO, NOME_DO_AGENTE
from api.erros import NaoEncontrado, PedidoInvalido, SemAuditor, TransicaoInvalida, TransicaoProibida
from api.servicos.armazenamento import Repositorio

ARQUIVO_FILA = "fila.json"
ARQUIVO_INCIDENTES = "incidentes.json"


class Estado(str, Enum):
    RECEBIDO = "recebido"
    EXTRAIDO = "extraido"
    DUPLICADO = "duplicado"
    EXCECAO = "excecao"
    LIBERADO = "liberado"
    RECUSADO = "recusado"


# Quem pode levar cada estado a qual. Fora desta tabela, nada se move.
TRANSICOES = {
    Estado.RECEBIDO: {Estado.EXTRAIDO, Estado.DUPLICADO, Estado.EXCECAO},
    Estado.EXCECAO: {Estado.LIBERADO, Estado.RECUSADO},
}


def _agora() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def hash_do_conteudo(conteudo: str) -> str:
    return hashlib.sha256(conteudo.encode("utf-8")).hexdigest()


class ServicoFila:
    def __init__(self, repo: Repositorio) -> None:
        self.repo = repo

    def _itens(self) -> list[dict]:
        return self.repo.ler_json(ARQUIVO_FILA, [])

    def _gravar(self, itens: list[dict]) -> None:
        self.repo.gravar_json(ARQUIVO_FILA, itens)

    # ------------------------------------------------------------- entrada
    def criar(self, arquivo: str, conteudo: str, origem: str = "manual") -> dict:
        if not (arquivo or "").strip() or not (conteudo or "").strip():
            raise PedidoInvalido("Item sem arquivo ou sem conteúdo.",
                                 como_resolver="Envie 'arquivo' e 'conteudo'.")
        with self.repo.trava:
            itens = self._itens()
            numero = max((int(i["id"][2:]) for i in itens), default=0) + 1
            item = {"id": f"d-{numero:04d}", "arquivo": arquivo, "origem": origem,
                    "hash": hash_do_conteudo(conteudo), "conteudo": conteudo,
                    "estado": Estado.RECEBIDO.value, "criado_em": _agora(),
                    "resultado": None, "historico": []}
            itens.append(item)
            self._gravar(itens)
            return item

    # ------------------------------------------------------------- leitura
    def listar(self, estado: str | None = None) -> list[dict]:
        itens = self._itens()
        return [i for i in itens if estado is None or i["estado"] == estado]

    def obter(self, id_item: str) -> dict:
        itens = self._itens()
        for item in itens:
            if item["id"] == id_item:
                return self._com_contexto(item, itens)
        raise NaoEncontrado(f"Item {id_item} não existe.", como_resolver="Liste com GET /fila.")

    def proximo(self) -> dict | None:
        """O mais antigo ainda RECEBIDO. É o estado que diz ao agente o que fazer agora."""
        itens = self._itens()
        for item in itens:
            if item["estado"] == Estado.RECEBIDO.value:
                return self._com_contexto(item, itens)
        return None

    @staticmethod
    def _com_contexto(item: dict, itens: list[dict]) -> dict:
        """Acrescenta o que o agente precisa saber e não tem como descobrir sozinho."""
        anteriores = [i["id"] for i in itens
                      if i["hash"] == item["hash"] and i["id"] < item["id"]
                      and i["estado"] != Estado.RECEBIDO.value]
        return {**item, "possivel_duplicado_de": anteriores[0] if anteriores else None}

    # ------------------------------------------------------------- transições
    def mover(self, id_item: str, para: str, por: str, dados: dict | None = None,
              motivo: str = "", tipo_excecao: str | None = None) -> dict:
        try:
            destino = Estado(para)
        except ValueError as exc:
            raise TransicaoInvalida(f"Estado '{para}' não existe.",
                                    como_resolver=f"Use um de: {[e.value for e in Estado]}") from exc
        with self.repo.trava:
            itens = self._itens()
            item = next((i for i in itens if i["id"] == id_item), None)
            if item is None:
                raise NaoEncontrado(f"Item {id_item} não existe.", como_resolver="Liste com GET /fila.")
            atual = Estado(item["estado"])

            if atual is Estado.EXCECAO and por == NOME_DO_AGENTE:
                raise TransicaoProibida(
                    "Exceção não volta para o agente, mesmo que ele ache que sabe resolver.",
                    como_resolver="Só um auditor humano libera ou recusa uma exceção (aba Exceções).")
            if destino not in TRANSICOES.get(atual, set()):
                raise TransicaoInvalida(
                    f"Não existe transição de '{atual.value}' para '{destino.value}'.",
                    como_resolver="Confira o estado atual com GET /fila/{id}. Estado final não se reabre.")

            item["estado"] = destino.value
            item["historico"].append({"de": atual.value, "para": destino.value, "por": por,
                                      "quando": _agora(), "motivo": motivo})
            if dados is not None:
                item["resultado"] = dados
            if destino is Estado.EXCECAO:
                item["motivo_excecao"] = motivo
                item["tipo_excecao"] = tipo_excecao or "regra"
                if tipo_excecao == "seguranca":
                    self._registrar_incidente(item, motivo, por)
            self._gravar(itens)
            return self._com_contexto(item, itens)

    def resolver(self, id_item: str, decisao: str, auditor: str | None, motivo: str = "") -> dict:
        nome = (auditor or "").strip()
        if not nome or nome.lower() == NOME_DO_AGENTE:
            raise SemAuditor("Resolver exceção exige um auditor humano identificado.",
                             como_resolver="Envie o cabeçalho X-Auditor com o SEU nome.")
        mapa = {"liberar": Estado.LIBERADO.value, "recusar": Estado.RECUSADO.value}
        if decisao not in mapa:
            raise PedidoInvalido("Decisão inválida.", como_resolver="Use 'liberar' ou 'recusar'.")
        return self.mover(id_item, mapa[decisao], por=nome, motivo=motivo)

    # ------------------------------------------------------------- incidentes e painel
    def _registrar_incidente(self, item: dict, motivo: str, por: str) -> None:
        incidentes = self.repo.ler_json(ARQUIVO_INCIDENTES, [])
        incidentes.append({"item": item["id"], "arquivo": item["arquivo"], "motivo": motivo,
                           "detectado_por": por, "quando": _agora()})
        self.repo.gravar_json(ARQUIVO_INCIDENTES, incidentes)

    def incidentes(self) -> list[dict]:
        return self.repo.ler_json(ARQUIVO_INCIDENTES, [])

    def painel(self) -> dict:
        itens = self._itens()
        por_estado = {e.value: sum(1 for i in itens if i["estado"] == e.value) for e in Estado}
        processados = [i for i in itens if i["estado"] != Estado.RECEBIDO.value]
        devolvidos = [i for i in processados
                      if any(h["para"] == Estado.EXCECAO.value for h in i["historico"])]
        taxa = round(len(devolvidos) / len(processados), 3) if processados else 0.0
        return {"por_estado": por_estado, "processados": len(processados),
                "devolvidos_para_humano": len(devolvidos), "taxa_de_devolucao": taxa,
                "alerta": taxa > ALERTA_DEVOLUCAO,
                "leitura": ("Mais de 30% param em exceção: o problema é a regra, não o modelo."
                            if taxa > ALERTA_DEVOLUCAO else "Dentro do esperado.")}
