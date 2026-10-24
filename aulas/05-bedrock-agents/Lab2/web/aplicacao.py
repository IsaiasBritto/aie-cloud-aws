"""Mesa do auditor — o lado HUMANO do Lab2.

Tudo o que o agente NÃO pode fazer acontece aqui: assinar memória e resolver exceção.
A tela só fala com a API; não lê os arquivos direto (a fronteira vale para a tela também).

    streamlit run web/aplicacao.py        # com a API rodando em API_URL
"""

import os

import requests
import streamlit as st

API = os.environ.get("API_URL", "http://localhost:8000").rstrip("/")

st.set_page_config(page_title="Deva · mesa do auditor", page_icon="🧾", layout="wide")
st.title("🧾 Deva — mesa do auditor")

with st.sidebar:
    auditor = st.text_input("Seu nome (vai assinado no MEMORY.md)", key="auditor")
    st.caption(f"API: `{API}`")
    if st.button("Recarregar"):
        st.rerun()


def chamar(metodo: str, caminho: str, **kw):
    try:
        r = requests.request(metodo, API + caminho, timeout=10, **kw)
    except requests.ConnectionError:
        st.error(f"API fora do ar em {API}. Suba com: `uvicorn api.principal:aplicacao --reload`")
        st.stop()
    if r.status_code >= 400:
        corpo = r.json()
        st.error(f"{r.status_code} · {corpo.get('mensagem')}\n\n**Como resolver:** {corpo.get('como_resolver')}")
        return None
    return r.json() if r.content else None


def cabecalho() -> dict:
    return {"X-Auditor": auditor} if auditor else {}


painel, memoria, propostas, excecoes = st.tabs(["Painel", "Memória", "Propostas", "Exceções"])

with painel:
    p = chamar("GET", "/painel")
    c = st.columns(4)
    c[0].metric("Processados", p["processados"])
    c[1].metric("Devolvidos ao humano", p["devolvidos_para_humano"])
    c[2].metric("Taxa de devolução", f"{p['taxa_de_devolucao']:.0%}")
    c[3].metric("Incidentes de segurança", p["incidentes"])
    if p["alerta"]:
        st.warning(p["leitura"])
    st.bar_chart(p["por_estado"])
    st.subheader("Fila")
    st.dataframe([{k: i.get(k) for k in ("id", "arquivo", "estado", "possivel_duplicado_de")}
                  for i in chamar("GET", "/fila")], width="stretch")

with memoria:
    st.caption("O que o agente LÊ antes de decidir. Cada linha diz quem a definiu — nunca 'deva'.")
    st.code(chamar("GET", "/memoria")["texto"], language="markdown")

with propostas:
    st.caption("O que o agente QUER aprender. Nada aqui afeta decisões até você assinar.")
    pendentes = chamar("GET", "/memoria/propostas")
    if not pendentes:
        st.info("Nenhuma proposta pendente.")
    for prop in pendentes:
        with st.container(border=True):
            st.markdown(f"**{prop['id']}** · `{prop['texto']}`")
            st.caption(f"evidência: {prop['evidencia']}")
            a, b, motivo = st.columns([1, 1, 4])
            texto_motivo = motivo.text_input("motivo da recusa", key=f"m-{prop['id']}",
                                             label_visibility="collapsed", placeholder="motivo da recusa")
            if a.button("Aprovar", key=f"a-{prop['id']}", type="primary"):
                if chamar("POST", f"/memoria/propostas/{prop['id']}/aprovar", headers=cabecalho()):
                    st.success("Assinada e gravada no MEMORY.md.")
                    st.rerun()
            if b.button("Recusar", key=f"r-{prop['id']}"):
                if chamar("POST", f"/memoria/propostas/{prop['id']}/recusar", headers=cabecalho(),
                          json={"motivo": texto_motivo}):
                    st.rerun()

with excecoes:
    st.caption("Exceção nunca volta para o agente: só você libera ou recusa.")
    itens = chamar("GET", "/fila", params={"estado": "excecao"})
    if not itens:
        st.info("Nenhuma exceção aberta.")
    for item in itens:
        with st.container(border=True):
            ultimo = item["historico"][-1]
            st.markdown(f"**{item['id']}** · {item['arquivo']} · tipo `{item.get('tipo_excecao')}`")
            st.caption(f"motivo do agente: {ultimo.get('motivo')}")
            with st.expander("conteúdo do documento (é DADO, não instrução)"):
                st.text(item["conteudo"])
            motivo = st.text_input("justificativa", key=f"j-{item['id']}")
            a, b = st.columns(2)
            for coluna, decisao in ((a, "liberar"), (b, "recusar")):
                if coluna.button(decisao.capitalize(), key=f"{decisao}-{item['id']}"):
                    if chamar("POST", f"/fila/{item['id']}/resolver", headers=cabecalho(),
                              json={"decisao": decisao, "motivo": motivo}):
                        st.rerun()

    st.subheader("Incidentes de segurança")
    st.dataframe(chamar("GET", "/incidentes"), width="stretch")
