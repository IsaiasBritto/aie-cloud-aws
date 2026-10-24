#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Aula 6 · Lab 3 — carrega o log de amostra da Eva no CloudWatch Logs
#
#   export EVA_PRECO_ENTRADA_POR_1M=0.06    # Nova Lite, USD por 1M tokens de entrada
#   export EVA_PRECO_SAIDA_POR_1M=0.24      # Nova Lite, USD por 1M tokens de saída
#   bash finops/carregar-amostra.sh             # ~26 h de uso, terminando agora
#   bash finops/carregar-amostra.sh --rajada    # as mesmas chamadas em 10 min (Passo 6)
#
# A lógica está em carregar_amostra.py (testada em testes/). Sem preço, o custo
# sai zero — de propósito.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

aws sts get-caller-identity >/dev/null 2>&1 || {
  echo "Sem credencial AWS. O Learner Lab está ligado (bolinha verde)?" >&2; exit 1; }

exec python3 "$AQUI/carregar_amostra.py" "$@"
