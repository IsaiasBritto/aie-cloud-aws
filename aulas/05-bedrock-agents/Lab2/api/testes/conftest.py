import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "gatilho"))

from api.configuracao import SEMENTE_MEMORIA  # noqa: E402
from api.principal import criar_aplicacao  # noqa: E402
from api.servicos.armazenamento import Repositorio  # noqa: E402
from api.servicos.fila import ServicoFila  # noqa: E402
from api.servicos.memoria import ServicoMemoria  # noqa: E402


@pytest.fixture
def repo(tmp_path):
    return Repositorio(tmp_path, SEMENTE_MEMORIA)


@pytest.fixture
def memoria(repo):
    return ServicoMemoria(repo)


@pytest.fixture
def fila(repo):
    return ServicoFila(repo)


@pytest.fixture
def http(tmp_path):
    return TestClient(criar_aplicacao(tmp_path))


@pytest.fixture
def cliente(http):
    from cliente import ClienteApi

    return ClienteApi(base="", sessao=http)
