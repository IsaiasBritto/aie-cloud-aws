"""Configuração por variáveis de ambiente — nada de valor fixo espalhado no código."""

from __future__ import annotations

import os
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# Onde moram os arquivos vivos do agente: MEMORY.md, memoria-pendente.md, fila.json...
# Fora do Git (dados/ está no .gitignore). O MEMORY.md da raiz do Lab2 é a SEMENTE.
DIRETORIO_DADOS = Path(os.getenv("DEVA_DADOS", RAIZ / "dados"))
SEMENTE_MEMORIA = RAIZ / "MEMORY.md"

# Fila de aprendizado: acima disso o agente para de propor até alguém revisar.
TETO_PENDENTES = int(os.getenv("DEVA_TETO_PENDENTES", "50"))

# O nome que o agente usa ao chamar a API. Nunca pode assinar memória nem liberar exceção.
NOME_DO_AGENTE = "deva"

# Acima desta taxa de devolução (exceções / processados), o painel acende o alerta.
ALERTA_DEVOLUCAO = float(os.getenv("DEVA_ALERTA_DEVOLUCAO", "0.30"))
