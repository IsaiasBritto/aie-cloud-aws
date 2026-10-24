# Atalhos do Lab2 (Deva contínuo). Digite `make` para ver a lista.

.DEFAULT_GOAL := ajuda
.PHONY: ajuda instalar testar api web semear volta demos provisionar enviar drenar limpar

ajuda:  ## Mostra esta lista
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	 awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

instalar:  ## Instala as dependências
	python -m pip install -r requirements.txt

testar:  ## Roda os testes (sem rede, sem AWS)
	python -m pytest

api:  ## Sobe a API em http://localhost:8000 (docs em /docs)
	uvicorn api.principal:aplicacao --reload --port 8000

web:  ## Sobe a mesa do auditor (Streamlit)
	API_URL=http://localhost:8000 streamlit run web/aplicacao.py

semear:  ## Coloca as 3 notas de amostra na fila
	python gatilho/disparador.py --semear

volta:  ## Uma volta do agente (sem LLM). Rode 4 vezes.
	python gatilho/ciclo_do_agente.py --uma-volta

demos:  ## As três tentativas que a fronteira barra: 403, 409, 422
	python gatilho/ciclo_do_agente.py --tentar-aprovar
	python gatilho/ciclo_do_agente.py --tentar-liberar
	python gatilho/ciclo_do_agente.py --injecao

provisionar:  ## Cria bucket, regra, Lambda e SQS (Learner Lab)
	terraform -chdir=infra/terraform init -input=false
	terraform -chdir=infra/terraform apply -auto-approve

enviar:  ## Envia as amostras para s3://<bucket>/entrada/
	python gatilho/disparador.py --s3 $$(terraform -chdir=infra/terraform output -raw bucket)

drenar:  ## Lê a SQS e põe os itens na fila da API
	python gatilho/disparador.py --sqs $$(terraform -chdir=infra/terraform output -raw fila_url)

limpar:  ## Apaga tudo na AWS
	bash infra/99-remover-tudo.sh
