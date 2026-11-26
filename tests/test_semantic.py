"""Testes do catálogo semântico: glossário, medidas e artefatos gerados nunca divergem."""
import re
from pathlib import Path

from src.semantic import gerar
from src.semantic.catalogo import CONCEITOS, MEDIDAS

ROOT = Path(__file__).resolve().parents[1]


def test_catalogo_e_dax_tem_as_mesmas_medidas():
    gerar.validar(gerar.carregar_dax())  # SystemExit se divergir


def test_referencias_entre_medidas_existem():
    dax = gerar.carregar_dax()
    for nome, expr in dax.items():
        # [Algo] sem tabela antes = referência a medida (colunas aparecem como Tabela[Coluna])
        refs = re.findall(r"(?<![\w'\]])\[([^\]]+)\]", expr)
        for r in refs:
            if r.startswith("@"):        # colunas de ADDCOLUMNS
                continue
            assert r in MEDIDAS, f"'{nome}' referencia medida inexistente [{r}]"


def test_artefatos_gerados_estao_atualizados():
    dax = gerar.carregar_dax()
    regs = gerar.registros(dax)
    assert (ROOT / "powerbi" / "medidas.dax").read_text(encoding="utf-8") == gerar.gerar_dax(dax)
    assert (ROOT / "sql" / "09_glossario.sql").read_text(encoding="utf-8") == gerar.gerar_sql(regs)
    assert (ROOT / "docs" / "glossario.md").read_text(encoding="utf-8") == gerar.gerar_md(regs)
    assert (ROOT / "powerbi" / "medidas_uma_a_uma.md").read_text(encoding="utf-8") == gerar.gerar_roteiro(dax)


def test_glossario_tem_medidas_e_conceitos_com_definicao():
    regs = gerar.registros(gerar.carregar_dax())
    assert sum(r["Tipo"] == "Medida" for r in regs) == len(MEDIDAS)
    assert sum(r["Tipo"] == "Conceito" for r in regs) == len(CONCEITOS)
    assert all(r["Definicao"].strip() and r["Calculo"].strip() for r in regs)
    # termos únicos como o SQL Server compara (collation padrão: sem diferenciar maiúsculas/minúsculas)
    assert len({r["Termo"].casefold() for r in regs}) == len(regs)


def test_dax_do_documento_igual_ao_catalogo():
    """powerbi/dax_measures.md (explicativo) e medidas_dax.json (fonte do gerador) têm o mesmo código."""
    assert gerar.extrair_dax_do_md() == gerar.carregar_dax()


def test_ordem_de_criacao_respeita_dependencias():
    """No roteiro uma a uma, nenhuma medida pode depender de outra criada depois dela."""
    dax, ordem = gerar.carregar_dax(), gerar.ordenadas()
    pos = {n: i for i, n in enumerate(ordem)}
    for nome in ordem:
        for r in re.findall(r"(?<![\w'\]])\[([^\]@][^\]]*)\]", dax[nome]):
            assert pos[r] < pos[nome], f"'{nome}' (posição {pos[nome]+1}) usa '{r}' (posição {pos[r]+1}), criada depois"
