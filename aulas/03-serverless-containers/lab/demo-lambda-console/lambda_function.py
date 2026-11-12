"""consultar_estoque como função Lambda: a tool do recap da Aula 3, criada na mão pelo console da AWS.

Só biblioteca padrão: cole este arquivo inteiro no editor de código do console e clique em Deploy.
"""
import json

# Estoque de exemplo. Em produção, viria de um banco, de um ERP ou de uma API de inventário.
ESTOQUE = {
    ("P001", "SP"): {"nome": "Café Especial 500g", "quantidade": 42},
    ("P001", "RJ"): {"nome": "Café Especial 500g", "quantidade": 0},
    ("P002", "SP"): {"nome": "Cadeira Ergonômica DXRacer", "quantidade": 15},
}


def consultar_estoque(produto_id: str, armazem_id: str) -> dict:
    """A mesma função do slide de recap: recebe produto e armazém, devolve o estoque."""
    item = ESTOQUE.get((produto_id, armazem_id))
    if item is None:
        return {"produto_id": produto_id, "armazem": armazem_id, "encontrado": False}
    return {
        "produto_id": produto_id,
        "nome": item["nome"],
        "quantidade_disponivel": item["quantidade"],
        "em_estoque": item["quantidade"] > 0,
        "armazem": armazem_id,
    }


def lambda_handler(event, context):
    """Ponto de entrada que a Lambda chama.

    Botão Test do console: o evento é o próprio JSON do evento de teste.
    Function URL:      os parâmetros chegam em queryStringParameters.
    """
    params = event.get("queryStringParameters") or event
    produto_id = params.get("produto_id")
    armazem_id = params.get("armazem_id", "SP")

    if not produto_id:
        return {"statusCode": 400, "body": json.dumps({"erro": "informe produto_id"})}

    print(f"consulta produto={produto_id} armazem={armazem_id}")  # vai para o CloudWatch Logs
    resultado = consultar_estoque(produto_id, armazem_id)
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(resultado, ensure_ascii=False),
    }
