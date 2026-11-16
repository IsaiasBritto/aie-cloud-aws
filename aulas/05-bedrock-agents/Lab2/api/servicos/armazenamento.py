"""Armazenamento em arquivos, de propósito.

Memória é um arquivo, com dono, permissão e retenção — não uma caixa-preta.
O aluno abre o MEMORY.md num editor e vê o que o agente sabe.

Em produção, troque por S3 (MEMORY.md versionado) e DynamoDB (fila). A interface
desta classe é o que fica: ler/gravar texto e ler/gravar JSON.
"""

from __future__ import annotations

import json
import shutil
import threading
from pathlib import Path
from typing import Any


class Repositorio:
    def __init__(self, diretorio: Path, semente_memoria: Path) -> None:
        self.diretorio = Path(diretorio)
        self.semente_memoria = Path(semente_memoria)
        self.trava = threading.RLock()
        self._garantir()

    def _garantir(self) -> None:
        """Recria a pasta e a semente do MEMORY.md se alguém apagou dados/ com a API no ar."""
        self.diretorio.mkdir(parents=True, exist_ok=True)
        memoria = self.diretorio / "MEMORY.md"
        if not memoria.exists():
            shutil.copyfile(self.semente_memoria, memoria)

    def caminho(self, nome: str) -> Path:
        return self.diretorio / nome

    def ler_texto(self, nome: str) -> str:
        with self.trava:
            self._garantir()
        p = self.caminho(nome)
        return p.read_text(encoding="utf-8") if p.exists() else ""

    def gravar_texto(self, nome: str, conteudo: str) -> None:
        with self.trava:
            self._garantir()
            p = self.caminho(nome)
            temporario = p.with_suffix(p.suffix + ".tmp")
            temporario.write_text(conteudo, encoding="utf-8")
            temporario.replace(p)  # troca atômica: ninguém lê arquivo pela metade

    def ler_json(self, nome: str, padrao: Any) -> Any:
        texto = self.ler_texto(nome)
        return json.loads(texto) if texto.strip() else padrao

    def gravar_json(self, nome: str, dado: Any) -> None:
        self.gravar_texto(nome, json.dumps(dado, ensure_ascii=False, indent=2))
