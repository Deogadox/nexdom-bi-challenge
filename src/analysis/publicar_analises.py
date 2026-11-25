"""
Publica no DW (SQL Server) os resultados estatísticos de src/analysis/analises.py,
para o Power BI consumir tudo a partir do banco.

Carga transacional (DELETE + INSERT) e conferência de contagem; as chaves SkOperadora/SkCobertura vêm do próprio
DW exportado, então os resultados se ligam a DW.DimOperadora sem nova busca por registro ANS.

Uso:  python -m src.analysis.publicar_analises
"""
from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd

# Permite rodar tanto "python -m src.x.y" quanto o arquivo direto (ex.: botão Run do VS Code)
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

ROOT = Path(__file__).resolve().parents[2]
ANA = ROOT / "data" / "processed" / "analises"
log = logging.getLogger("publicar_analises")


def preparar_r2() -> pd.DataFrame:
    d = pd.read_csv(ANA / "r2_operadoras_igr_12m.csv")
    import json
    jan = json.loads((ANA / "resultados.json").read_text(encoding="utf-8"))["R2"]["janela"]
    return pd.DataFrame({
        "SkOperadora": d.SkOperadora, "SkCobertura": d.SkCobertura,
        "JanelaInicio": int(jan[0]), "JanelaFim": int(jan[1]),
        "Reclamacoes": d.Reclamacoes, "BenefSoma": d.BenefSoma, "BenefMedio": d.BenefMedio.round(1),
        "Meses": d.Meses, "IGR": d.IGR.round(4), "PorteUltimoMes": d.Porte, "Elegivel": d.Elegivel,
        "Esperado": d.Esperado.round(4), "ZFunil": d.ZFunil.round(4),
        "LimInfIGR": d.LimInfIGR.round(4), "LimSupIGR": d.LimSupIGR.round(4), "Funil": d.Funil,
        "IQRSegmento": d.IQR_Segmento.fillna("n/a"), "ZRobSegmento": d.ZRob_Segmento.round(4),
        "OutlierConsistente": d.OutlierConsistente})


def preparar_r1() -> pd.DataFrame:
    d = pd.read_csv(ANA / "r1_operadoras_igr_tr.csv")
    import json
    jan = json.loads((ANA / "resultados.json").read_text(encoding="utf-8"))["R1"]["janela"]
    col = lambda c: d[c] if c in d else None  # noqa: E731
    return pd.DataFrame({
        "SkOperadora": d.SkOperadora, "SkCobertura": d.SkCobertura, "GrupoAssistencial": d.GrupoAssistencial,
        "JanelaInicio": int(jan[0]), "JanelaFim": int(jan[1]),
        "Reclamacoes": d.Reclamacoes, "BenefMedio": d.BenefMedio.round(1), "IGR": d.IGR.round(4),
        "Demandas": d.Demandas, "Resolvidas": d.Resolvidas, "TRGeral": d.TR_Geral.round(4),
        "TRAssistencial": col("TR_Assistencial").round(4), "TRNaoAssistencial": col("TR_Não Assistencial").round(4),
        "Elegivel": d.Elegivel, "ScoreIGR": d.Score_IGR.round(3), "ScoreTR": d.Score_TR.round(3),
        "IndiceCombinado": d.IndiceCombinado.round(3), "Quadrante": d.Quadrante})


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(name)s | %(message)s", stream=sys.stdout)
    from src.common.db import get_engine

    engine = get_engine()
    with engine.begin() as conn:
        for tabela, df in (("AnaliseR2Operadora", preparar_r2()), ("AnaliseR1Operadora", preparar_r1())):
            conn.exec_driver_sql(f"DELETE FROM DW.{tabela}")
            df.to_sql(tabela, conn, schema="DW", if_exists="append", index=False, chunksize=2000)
            n = conn.exec_driver_sql(f"SELECT COUNT(*) FROM DW.{tabela}").scalar_one()
            if n != len(df):
                raise RuntimeError(f"Contagem divergente em DW.{tabela}: arquivo={len(df)} banco={n}")
            log.info("DW.%s: %s linhas publicadas", tabela, n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
