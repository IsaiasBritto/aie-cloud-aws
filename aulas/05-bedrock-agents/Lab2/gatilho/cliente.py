"""Cliente HTTP mínimo da API de Continuidade.

O gatilho e o ciclo falam com a API só por HTTP — como o agente no Bedrock falaria.
Nos testes, a mesma classe recebe o TestClient do FastAPI no lugar do requests.
"""

from __future__ import annotations

import os

API_URL = os.getenv("API_URL", "http://localhost:8000")


class ClienteApi:
    def __init__(self, base: str = API_URL, sessao=None) -> None:
        if sessao is None:
            import requests

            sessao = requests.Session()
        self.base = base.rstrip("/")
        self.sessao = sessao

    def get(self, caminho: str, **kw):
        return self.sessao.get(f"{self.base}{caminho}", **kw)

    def post(self, caminho: str, json=None, headers=None):
        return self.sessao.post(f"{self.base}{caminho}", json=json, headers=headers or {})
