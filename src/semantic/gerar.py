"""
Gera os artefatos semânticos a partir do catálogo único (src/semantic/catalogo.py + medidas_dax.json):
  powerbi/medidas.dax    — todas as medidas para a Exibição de consulta DAX ("Atualizar modelo")
  sql/09_glossario.sql   — DW.Glossario (medidas + conceitos) para a página "Glossário" do dashboard
  docs/glossario.md      — glossário legível no GitHub

Falha se houver medida com DAX e sem definição (ou o contrário): o glossário nunca diverge do modelo.
Uso:  python -m src.semantic.gerar
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from src.semantic.catalogo import CONCEITOS, MEDIDAS

ROOT = Path(__file__).resolve().parents[2]
TABELA_MEDIDAS = "Medidas"
PASTAS = ["0 Parâmetros", "1 IGR", "2 TR", "3 Tempo", "4 Ranking", "5 Concentração", "6 Estatística", "7 UX"]


def carregar_dax() -> dict[str, str]:
    return json.loads((ROOT / "src" / "semantic" / "medidas_dax.json").read_text(encoding="utf-8"))


def extrair_dax_do_md(md: Path = ROOT / "powerbi" / "dax_measures.md") -> dict[str, str]:
    """Lê as medidas dos blocos ```DAX do documento explicativo (medidas separadas por linha em branco)."""
    import re
    out: dict[str, str] = {}
    for bloco_dax in re.findall(r"```DAX\n(.*?)```", md.read_text(encoding="utf-8"), re.S):
        for bloco in re.split(r"\n\s*\n", bloco_dax.strip()):
            l0, *resto = bloco.split("\n")
            if l0.rstrip().endswith(" ="):
                nome, expr = l0.rstrip()[:-2], "\n".join(resto)
            else:
                nome, expr = l0.split(" = ", 1)
                expr = "\n".join([expr] + resto)
            out[nome.strip()] = expr.strip()
    return out


def validar(dax: dict[str, str]) -> None:
    sem_def, sem_dax = set(dax) - set(MEDIDAS), set(MEDIDAS) - set(dax)
    if sem_def or sem_dax:
        raise SystemExit(f"Catálogo inconsistente. Sem definição: {sorted(sem_def)} | Sem DAX: {sorted(sem_dax)}")
    for nome, m in MEDIDAS.items():
        faltando = [k for k in ("pasta", "formato", "unidade", "sentido", "definicao", "calculo") if k not in m]
        if faltando or m["pasta"] not in PASTAS:
            raise SystemExit(f"Medida '{nome}': campos ausentes {faltando} ou pasta inválida '{m.get('pasta')}'")


def ordenadas() -> list[str]:
    return sorted(MEDIDAS, key=lambda n: (PASTAS.index(MEDIDAS[n]["pasta"]), list(MEDIDAS).index(n)))


# ----------------------------------------------------------------------------- DAX
def gerar_dax(dax: dict[str, str]) -> str:
    linhas = [
        "// ============================================================================================",
        "// GERADO por src/semantic/gerar.py a partir de src/semantic/catalogo.py — não edite à mão.",
        "// Como usar (Power BI Desktop):",
        "//   1. Crie antes a tabela 'Medidas' e os parâmetros 'Peso IGR' e 'Benef Mínimo' (powerbi/README.md).",
        "//   2. Abra a Exibição de consulta DAX, cole este arquivo inteiro e clique no link",
        "//      'Atualizar modelo: adicionar ... novas medidas' que aparece acima de DEFINE.",
        "//   3. Ajuste formato e pasta de exibição de cada medida (comentário '// pasta | formato' acima dela).",
        "//   Linhas '///' são a descrição da medida.",
        "// ============================================================================================",
        "DEFINE",
    ]
    pasta_atual = None
    for nome in ordenadas():
        m = MEDIDAS[nome]
        if m["pasta"] != pasta_atual:
            pasta_atual = m["pasta"]
            linhas += ["", f"    // ---------------------------------------------------------------- {pasta_atual}"]
        corpo = dax[nome].replace("\n", "\n        ")
        linhas += [f"    /// {m['definicao']}",
                   f"    // pasta: {m['pasta']} | formato: {m['formato'] or '(texto)'}",
                   f"    MEASURE {TABELA_MEDIDAS}[{nome}] =",
                   f"        {corpo}"]
    linhas += ["", "EVALUATE", '    ROW ( "IGR", [IGR], "TR", [TR], "Operadoras com IGR", [Operadoras com IGR] )', ""]
    return "\n".join(linhas)


# ----------------------------------------------------------------------------- SQL
def q(v) -> str:
    return "NULL" if v in (None, "") else "N'" + str(v).replace("'", "''") + "'"


def registros(dax: dict[str, str]) -> list[dict]:
    out, ordem = [], 0
    for nome in ordenadas():
        ordem += 1
        m = MEDIDAS[nome]
        out.append(dict(Ordem=ordem, Tipo="Medida", Termo=nome, Pasta=m["pasta"], Definicao=m["definicao"],
                        Calculo=m["calculo"], Unidade=m["unidade"], Sentido=m["sentido"], Formato=m["formato"],
                        Observacao=m.get("obs", ""), ExpressaoDAX=dax[nome]))
    for c in CONCEITOS:
        ordem += 1
        out.append(dict(Ordem=ordem, Tipo="Conceito", Termo=c["termo"], Pasta="Conceitos", Definicao=c["definicao"],
                        Calculo=c["calculo"], Unidade="", Sentido="", Formato="", Observacao=c.get("obs", ""), ExpressaoDAX=""))
    return out


def gerar_sql(regs: list[dict]) -> str:
    cols = ["Ordem", "Tipo", "Termo", "Pasta", "Definicao", "Calculo", "Unidade", "Sentido", "Formato", "Observacao", "ExpressaoDAX"]
    valores = ",\n".join(
        "    (" + ", ".join(str(r[c]) if c == "Ordem" else q(r[c]) for c in cols) + ")" for r in regs)
    return f"""/* =====================================================================================
   09_glossario.sql — DW.Glossario: definição de todas as medidas e conceitos do dashboard
   GERADO por src/semantic/gerar.py a partir de src/semantic/catalogo.py — não edite à mão.
   Idempotente: recria o conteúdo a cada execução (a tabela é derivada inteiramente do catálogo).
   Execução: sqlcmd -S localhost -E -b -I -f 65001 -i sql\\09_glossario.sql
   ===================================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
USE ANS_BI;
GO
IF OBJECT_ID(N'DW.Glossario', N'U') IS NULL
CREATE TABLE DW.Glossario (
    Ordem         SMALLINT       NOT NULL CONSTRAINT PK_DW_Glossario PRIMARY KEY,
    Tipo          NVARCHAR(10)   NOT NULL CONSTRAINT CK_DW_Glossario_Tipo CHECK (Tipo IN (N'Medida', N'Conceito')),
    Termo         NVARCHAR(80)   NOT NULL CONSTRAINT UQ_DW_Glossario_Termo UNIQUE,
    Pasta         NVARCHAR(30)   NOT NULL,     -- pasta de exibição no Power BI (ou "Conceitos")
    Definicao     NVARCHAR(600)  NOT NULL,     -- o que é, em linguagem de negócio
    Calculo       NVARCHAR(600)  NOT NULL,     -- como é calculada
    Unidade       NVARCHAR(60)   NULL,
    Sentido       NVARCHAR(40)   NULL,         -- como ler: maior = melhor / pior
    Formato       NVARCHAR(30)   NULL,         -- string de formato no Power BI
    Observacao    NVARCHAR(600)  NULL,         -- cuidados e limitações
    ExpressaoDAX  NVARCHAR(MAX)  NULL,
    DtAtualizacao DATETIME2(0)   NOT NULL CONSTRAINT DF_DW_Glossario_Dt DEFAULT SYSDATETIME()
);
GO
SET XACT_ABORT ON;
BEGIN TRAN;
TRUNCATE TABLE DW.Glossario;
INSERT DW.Glossario ({", ".join(cols)})
VALUES
{valores};
COMMIT;
GO
SELECT Tipo, COUNT(*) AS Termos FROM DW.Glossario GROUP BY Tipo;
PRINT N'09_glossario.sql concluído: {sum(r["Tipo"] == "Medida" for r in regs)} medidas e {sum(r["Tipo"] == "Conceito" for r in regs)} conceitos.';
"""


# ----------------------------------------------------------------------------- Markdown
def md_cel(v: str) -> str:
    return (v or "").replace("|", "\\|").replace("\n", " ")


def gerar_md(regs: list[dict]) -> str:
    l = ["# Glossário de medidas e conceitos", "",
         "<!-- GERADO por src/semantic/gerar.py a partir de src/semantic/catalogo.py — não edite à mão. -->", "",
         "Fonte única: [`src/semantic/catalogo.py`](../src/semantic/catalogo.py). O mesmo conteúdo alimenta a tabela",
         "`DW.Glossario` (página *Glossário* do dashboard) e o arquivo [`powerbi/medidas.dax`](../powerbi/medidas.dax).",
         "O código DAX de cada medida está em [`powerbi/medidas.dax`](../powerbi/medidas.dax) e na coluna `ExpressaoDAX` da tabela.", ""]
    for pasta in PASTAS:
        itens = [r for r in regs if r["Pasta"] == pasta]
        l += [f"## {pasta}", "", "| Medida | Definição | Cálculo | Unidade | Leitura | Observação |", "|---|---|---|---|---|---|"]
        l += [f"| **{md_cel(r['Termo'])}** | {md_cel(r['Definicao'])} | {md_cel(r['Calculo'])} | {md_cel(r['Unidade'])} | "
              f"{md_cel(r['Sentido'])} | {md_cel(r['Observacao'])} |" for r in itens]
        l.append("")
    l += ["## Conceitos", "", "| Termo | Definição | Onde está no modelo | Observação |", "|---|---|---|---|"]
    l += [f"| **{md_cel(r['Termo'])}** | {md_cel(r['Definicao'])} | {md_cel(r['Calculo'])} | {md_cel(r['Observacao'])} |"
          for r in regs if r["Tipo"] == "Conceito"]
    return "\n".join(l) + "\n"


def main() -> int:
    dax = carregar_dax()
    validar(dax)
    regs = registros(dax)
    (ROOT / "powerbi" / "medidas.dax").write_text(gerar_dax(dax), encoding="utf-8")
    (ROOT / "sql" / "09_glossario.sql").write_text(gerar_sql(regs), encoding="utf-8")
    (ROOT / "docs" / "glossario.md").write_text(gerar_md(regs), encoding="utf-8")
    print(f"OK: {len(MEDIDAS)} medidas e {len(CONCEITOS)} conceitos → powerbi/medidas.dax, sql/09_glossario.sql, docs/glossario.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
