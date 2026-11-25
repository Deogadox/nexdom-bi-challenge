"""
Fase 7 — Análises estatísticas sobre o DW exportado (data/processed/dw/*.parquet).

Recortes (decisão documentada em docs/achados_exploracao.md, A1):
  R2 — "atual":   IGR série VIGENTE, últimos 12 meses disponíveis (sem TR — a ANS não publica TR após 2019-10)
  R1 — "conjunto": IGR × TR nos últimos 12 meses da janela comum (2018-05 → 2019-04)

Princípios:
  * Taxas de período = soma(numerador) / soma(denominador) — nunca média de taxas mensais.
  * IGR médico e odontológico têm escalas ~50× diferentes → toda comparação é feita dentro da cobertura
    (R2) ou do grupo assistencial (R1).
  * Volume mínimo para rankings/outliers (critérios em CRITERIOS); operadoras abaixo dele são preservadas
    nas tabelas com Elegivel = False, nunca descartadas silenciosamente.

Saídas: data/processed/analises/*.csv, reports/figures/*.png, data/processed/analises/resultados.json
Uso:    python -m src.analysis.analises [--dw data/processed/dw]
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

ROOT = Path(__file__).resolve().parents[2]
log = logging.getLogger("analises")

CRITERIOS = {
    "janela_meses": 12,
    "min_beneficiarios_medios": 5000,     # R2/R1: mantém 99,5% dos beneficiários (médico) e remove taxas instáveis
    "min_meses_com_dado": 12,             # operadora presente em todos os meses da janela
    "min_demandas_tr": 30,                # R1: TR com ≥ 30 demandas no ano (1 demanda ≤ 3,3 p.p.)
    "pesos_indice": {"igr": 0.5, "tr": 0.5},
    "funil_nivel": 0.998,                 # limites ~3σ (Spiegelhalter, 2005)
    "z_robusto_limite": 3.5,              # Iglewicz & Hoaglin
}
COB_MED, COB_ODO = 1, 2
NOME_COB = {COB_MED: "Assistência médica", COB_ODO: "Exclusivamente odontológica"}
GRUPO_COB = {"Médico-hospitalar": COB_MED, "Odontológico": COB_ODO}


# ----------------------------------------------------------------------------- carga
def carregar(dw: Path) -> dict[str, pd.DataFrame]:
    t = {n: pd.read_parquet(dw / f"{n}.parquet") for n in
         ["DimOperadora", "DimSegmento", "DimTempo", "DimCobertura", "DimNatureza", "DimPorte", "FatoIGR", "FatoTR"]}
    op = t["DimOperadora"].merge(t["DimSegmento"], on="SkSegmento", how="left")
    t["Op"] = op[["SkOperadora", "RegistroANS", "NomeExibicao", "RazaoSocial", "Segmento", "GrupoAssistencial",
                  "Modalidade", "Situacao", "UF"]]
    return t


def meses_finais(skt: pd.Series, n: int) -> list[int]:
    return sorted(skt.unique())[-n:]


# ----------------------------------------------------------------------------- bases por operadora
def base_igr(t, meses: list[int]) -> pd.DataFrame:
    f = t["FatoIGR"][t["FatoIGR"].SkTempo.isin(meses)]
    ult = f[f.SkTempo == max(meses)][["SkOperadora", "SkCobertura", "SkPorte"]]
    g = (f.groupby(["SkOperadora", "SkCobertura"])
           .agg(Reclamacoes=("QtdReclamacoes", "sum"), BenefSoma=("QtdBeneficiarios", "sum"),
                Meses=("SkTempo", "nunique")).reset_index())
    g["BenefMedio"] = g.BenefSoma / g.Meses
    g["IGR"] = np.where(g.BenefSoma > 0, g.Reclamacoes / g.BenefSoma * 1e5, np.nan)
    g = g.merge(ult, on=["SkOperadora", "SkCobertura"], how="left") \
         .merge(t["DimPorte"][["SkPorte", "Porte"]], on="SkPorte", how="left") \
         .merge(t["Op"], on="SkOperadora", how="left")
    g["Porte"] = g.Porte.fillna("Sem dado no último mês")
    g["Cobertura"] = g.SkCobertura.map(NOME_COB)
    g["Elegivel"] = (g.Meses >= CRITERIOS["min_meses_com_dado"]) & (g.BenefMedio >= CRITERIOS["min_beneficiarios_medios"])
    return g.drop(columns=["SkPorte"])


def base_tr(t, meses: list[int]) -> pd.DataFrame:
    f = t["FatoTR"][t["FatoTR"].SkTempo.isin(meses)].merge(t["DimNatureza"], on="SkNatureza")
    p = f.pivot_table(index="SkOperadora", columns="Natureza", values=["Numerador", "Denominador"], aggfunc="sum")
    p.columns = [f"{a}_{b}" for a, b in p.columns]
    p = p.reset_index()
    for nat in ["Geral", "Assistencial", "Não Assistencial"]:
        num, den = p.get(f"Numerador_{nat}"), p.get(f"Denominador_{nat}")
        p[f"TR_{nat}"] = np.where(den > 0, num / den * 100, np.nan) if den is not None else np.nan
    return p.rename(columns={"Denominador_Geral": "Demandas", "Numerador_Geral": "Resolvidas"})


# ----------------------------------------------------------------------------- estatística
def pct_rank(s: pd.Series) -> pd.Series:
    return s.rank(pct=True, method="average")


def funil_poisson(df: pd.DataFrame, obs: str, expo: str, taxa_ref: float, nivel: float, por: float = 1e5) -> pd.DataFrame:
    """Funil de Poisson com ajuste de sobredispersão (Spiegelhalter, 2005).
    E = taxa_ref × exposição; z = (O − E)/√E; φ = média de z² winsorizado a 10%; limites ×√φ (se φ > 1)."""
    d = df.copy()
    E = taxa_ref * d[expo] / por
    z = (d[obs] - E) / np.sqrt(E)
    zw = z.clip(z.quantile(0.10), z.quantile(0.90))
    phi = float(max(1.0, (zw ** 2).mean()))
    zc = stats.norm.ppf(1 - (1 - nivel) / 2)
    d["Esperado"], d["ZFunil"] = E, z / np.sqrt(phi)
    d["LimSupIGR"] = (E + zc * np.sqrt(phi * E)) / d[expo] * por
    d["LimInfIGR"] = np.maximum(0, (E - zc * np.sqrt(phi * E)) / d[expo] * por)
    d["Funil"] = np.select([d.ZFunil > zc, d.ZFunil < -zc], ["Acima (pior)", "Abaixo (melhor)"], "Dentro")
    d.attrs["phi"] = phi
    return d


def z_robusto(x: pd.Series) -> pd.Series:
    med = x.median(); mad = (x - med).abs().median()
    return 0.6745 * (x - med) / mad if mad > 0 else pd.Series(0.0, index=x.index)


def flags_iqr(x: pd.Series) -> pd.Series:
    q1, q3 = x.quantile([.25, .75]); iqr = q3 - q1
    return np.select([x > q3 + 1.5 * iqr, x < q1 - 1.5 * iqr], ["Acima", "Abaixo"], "Dentro")


def correl(x: pd.Series, y: pd.Series, nome: str, recorte: str, filtro: str, log_x: bool = True, log_y: bool = True) -> dict:
    """Spearman (monotônica, robusta a assimetria/outliers) + Pearson com log1p apenas nas variáveis de escala
    assimétrica (beneficiários, reclamações, IGR). Percentuais limitados (TR) entram sem transformação."""
    m = x.notna() & y.notna()
    xs, ys = (np.log1p(x[m]) if log_x else x[m]), (np.log1p(y[m]) if log_y else y[m])
    sp = stats.spearmanr(x[m], y[m]); pe = stats.pearsonr(xs, ys)
    return {"Recorte": recorte, "Filtro": filtro, "Par": nome, "N": int(m.sum()),
            "Spearman_rho": round(float(sp.statistic), 3), "Spearman_p": float(sp.pvalue),
            "Pearson_r": round(float(pe.statistic), 3), "Pearson_p": float(pe.pvalue),
            "Pearson_transf": f"{'log' if log_x else 'linear'} × {'log' if log_y else 'linear'}"}


# ----------------------------------------------------------------------------- análises
def analise_r2(t, out: Path, res: dict) -> pd.DataFrame:
    fi = t["FatoIGR"].merge(t["DimTempo"][["SkTempo", "SerieIGR"]], on="SkTempo")
    meses = meses_finais(fi[fi.SerieIGR == "VIGENTE"].SkTempo, CRITERIOS["janela_meses"])
    b = base_igr(t, meses)
    res["R2"] = {"janela": [min(meses), max(meses)], "operadoras_por_cobertura": b.groupby("Cobertura").size().to_dict(),
                 "elegiveis_por_cobertura": b[b.Elegivel].groupby("Cobertura").size().to_dict()}

    partes = []
    for cob in (COB_MED, COB_ODO):
        x = b[b.SkCobertura == cob].copy()
        el = x[x.Elegivel]
        taxa = el.Reclamacoes.sum() / el.BenefSoma.sum() * 1e5
        x = funil_poisson(x, "Reclamacoes", "BenefSoma", taxa, CRITERIOS["funil_nivel"])
        res["R2"][f"IGR_mercado_{NOME_COB[cob]}"] = round(taxa, 2)
        res["R2"][f"phi_funil_{NOME_COB[cob]}"] = round(x.attrs["phi"], 1)
        # discrepância frente ao próprio segmento (entre elegíveis)
        x["IQR_Segmento"], x["ZRob_Segmento"] = "n/a", np.nan
        for seg, idx in x[x.Elegivel].groupby("Segmento").groups.items():
            if len(idx) >= 8:
                v = x.loc[idx, "IGR"]
                x.loc[idx, "IQR_Segmento"] = flags_iqr(v)
                x.loc[idx, "ZRob_Segmento"] = z_robusto(np.log1p(v))
        x["OutlierConsistente"] = x.Elegivel & (
            ((x.Funil == "Acima (pior)") & ((x.IQR_Segmento == "Acima") | (x.ZRob_Segmento > CRITERIOS["z_robusto_limite"])))
            | ((x.Funil == "Abaixo (melhor)") & ((x.IQR_Segmento == "Abaixo") | (x.ZRob_Segmento < -CRITERIOS["z_robusto_limite"]))))
        partes.append(x)
    b = pd.concat(partes, ignore_index=True)
    b.to_csv(out / "r2_operadoras_igr_12m.csv", index=False)

    # Rankings (somente elegíveis, por cobertura)
    cols = ["RegistroANS", "NomeExibicao", "Segmento", "Porte", "BenefMedio", "Reclamacoes", "IGR", "Funil"]
    for cob, tag in ((COB_MED, "medico"), (COB_ODO, "odonto")):
        el = b[(b.SkCobertura == cob) & b.Elegivel]
        el.nlargest(10, "IGR")[cols].to_csv(out / f"r2_top10_pior_igr_{tag}.csv", index=False)
        el.sort_values(["IGR", "BenefMedio"], ascending=[True, False]).head(10)[cols].to_csv(out / f"r2_top10_melhor_igr_{tag}.csv", index=False)
        res["R2"][f"zero_reclamacoes_elegiveis_{tag}"] = int((el.Reclamacoes == 0).sum())

    # Outliers
    b[b.Elegivel & (b.Funil != "Dentro")][cols + ["Cobertura", "Esperado", "ZFunil", "IQR_Segmento", "ZRob_Segmento", "OutlierConsistente"]] \
        .sort_values(["Cobertura", "ZFunil"], ascending=[True, False]).to_csv(out / "r2_outliers.csv", index=False)
    for cob in (COB_MED, COB_ODO):
        el = b[(b.SkCobertura == cob) & b.Elegivel]
        res["R2"][f"outliers_{NOME_COB[cob]}"] = {
            "funil_acima": int((el.Funil == "Acima (pior)").sum()), "funil_abaixo": int((el.Funil == "Abaixo (melhor)").sum()),
            "consistentes_acima": int((el.OutlierConsistente & (el.Funil == "Acima (pior)")).sum()),
            "consistentes_abaixo": int((el.OutlierConsistente & (el.Funil == "Abaixo (melhor)")).sum())}

    # Correlação porte × reclamações × IGR (operadora; médico; ≥ 12 meses, sem filtro de porte para não truncar o eixo)
    med_all = b[(b.SkCobertura == COB_MED) & (b.Meses >= 12) & (b.BenefMedio >= 1000)]
    med_el = b[(b.SkCobertura == COB_MED) & b.Elegivel]
    cor = [correl(med_all.BenefMedio, med_all.Reclamacoes, "Beneficiários × Reclamações (absoluto)", "R2", "médico, ≥1 mil benef."),
           correl(med_all.BenefMedio, med_all.IGR, "Beneficiários × IGR", "R2", "médico, ≥1 mil benef."),
           correl(med_el.BenefMedio, med_el.IGR, "Beneficiários × IGR", "R2", "médico, elegíveis (≥5 mil)")]

    # Porte
    porte = (med_el.groupby("Porte").agg(Operadoras=("SkOperadora", "count"), Reclamacoes=("Reclamacoes", "sum"),
                                         BenefSoma=("BenefSoma", "sum"), IGR_Mediana=("IGR", "median"),
                                         IGR_P25=("IGR", lambda s: s.quantile(.25)), IGR_P75=("IGR", lambda s: s.quantile(.75)))
                   .reset_index())
    porte["IGR_Agregado"] = porte.Reclamacoes / porte.BenefSoma * 1e5
    kw = stats.kruskal(*[g.IGR.values for _, g in med_el.groupby("Porte")])
    res["R2"]["kruskal_porte_medico"] = {"H": round(float(kw.statistic), 2), "p": float(kw.pvalue)}
    porte.to_csv(out / "r2_porte_medico.csv", index=False)

    # Segmentos (cada segmento na cobertura que lhe é própria)
    linhas = []
    for (seg, grp), x in b[b.Elegivel].groupby(["Segmento", "GrupoAssistencial"]):
        cob = GRUPO_COB.get(grp)
        x = x[x.SkCobertura == cob]
        if x.empty:
            continue
        linhas.append({"Segmento": seg, "Cobertura": NOME_COB[cob], "Operadoras": len(x),
                       "IGR_Agregado": x.Reclamacoes.sum() / x.BenefSoma.sum() * 1e5,
                       "IGR_Media": x.IGR.mean(), "IGR_Mediana": x.IGR.median(),
                       "IGR_P25": x.IGR.quantile(.25), "IGR_P75": x.IGR.quantile(.75),
                       "Beneficiarios_Medios": x.BenefMedio.sum(), "Reclamacoes": int(x.Reclamacoes.sum()),
                       "Outliers_Acima": int((x.OutlierConsistente & (x.Funil == "Acima (pior)")).sum())})
    seg = pd.DataFrame(linhas).sort_values(["Cobertura", "IGR_Agregado"], ascending=[True, False])
    seg.to_csv(out / "r2_segmentos.csv", index=False)
    medseg = med_el[med_el.GrupoAssistencial == "Médico-hospitalar"]
    kw2 = stats.kruskal(*[g.IGR.values for _, g in medseg.groupby("Segmento") if len(g) >= 5])
    res["R2"]["kruskal_segmentos_medico"] = {"H": round(float(kw2.statistic), 2), "p": float(kw2.pvalue)}

    # Concentração (médico, elegíveis)
    c = med_el.sort_values("Reclamacoes", ascending=False)
    res["R2"]["concentracao_medico"] = {
        "top10_share_reclamacoes": round(c.head(10).Reclamacoes.sum() / c.Reclamacoes.sum(), 3),
        "top10_share_beneficiarios": round(c.head(10).BenefSoma.sum() / c.BenefSoma.sum(), 3),
        "top10_por_reclamacoes": c.head(10)[["NomeExibicao", "Reclamacoes", "BenefMedio", "IGR"]].round(2).to_dict("records")}
    res["_cor"] = cor
    return b


def analise_r1(t, out: Path, res: dict) -> pd.DataFrame:
    jan = t["DimTempo"][t["DimTempo"].FlJanelaComumIGRTR == 1].SkTempo
    meses = meses_finais(jan, CRITERIOS["janela_meses"])
    bi, bt = base_igr(t, meses), base_tr(t, meses)
    bi = bi[bi.GrupoAssistencial.isin(GRUPO_COB)]
    bi = bi[bi.SkCobertura == bi.GrupoAssistencial.map(GRUPO_COB)]    # IGR da cobertura própria do segmento
    d = bi.merge(bt, on="SkOperadora", how="inner")
    d["Elegivel"] = d.Elegivel & (d.Demandas >= CRITERIOS["min_demandas_tr"])
    res["R1"] = {"janela": [min(meses), max(meses)], "operadoras_com_igr_e_tr": int(len(d)),
                 "elegiveis_por_grupo": d[d.Elegivel].groupby("GrupoAssistencial").size().to_dict()}

    w = CRITERIOS["pesos_indice"]
    partes = []
    for grp, x in d.groupby("GrupoAssistencial"):
        x = x.copy()
        el = x.Elegivel
        x.loc[el, "Score_IGR"] = 100 * (1 - pct_rank(x.loc[el, "IGR"]))       # menor IGR = melhor
        x.loc[el, "Score_TR"] = 100 * pct_rank(x.loc[el, "TR_Geral"])          # maior TR = melhor
        x.loc[el, "IndiceCombinado"] = w["igr"] * x.loc[el, "Score_IGR"] + w["tr"] * x.loc[el, "Score_TR"]
        for wi in (0.3, 0.7):
            x.loc[el, f"Indice_{int(wi*100)}_{int((1-wi)*100)}"] = wi * x.loc[el, "Score_IGR"] + (1 - wi) * x.loc[el, "Score_TR"]
        mi, mt = x.loc[el, "IGR"].median(), x.loc[el, "TR_Geral"].median()
        x.loc[el, "Quadrante"] = np.select(
            [(x.IGR > mi) & (x.TR_Geral < mt), (x.IGR <= mi) & (x.TR_Geral >= mt), (x.IGR > mi)],
            ["Crítico: IGR alto e TR baixa", "Referência: IGR baixo e TR alta", "IGR alto, TR alta"], "IGR baixo, TR baixa")[el]
        e = x[el]
        sens = {f"spearman_50_50_vs_{k}": round(float(stats.spearmanr(e.IndiceCombinado, e[k]).statistic), 3)
                for k in ("Indice_30_70", "Indice_70_30")}
        res["R1"][grp] = {"IGR_mediana": round(mi, 2), "TR_mediana": round(mt, 1),
                          "quadrantes": e.Quadrante.value_counts().to_dict(), "sensibilidade_pesos": sens}
        partes.append(x)
    d = pd.concat(partes, ignore_index=True)
    d.to_csv(out / "r1_operadoras_igr_tr.csv", index=False)
    cols = ["GrupoAssistencial", "RegistroANS", "NomeExibicao", "Segmento", "BenefMedio", "IGR", "TR_Geral", "Demandas",
            "Score_IGR", "Score_TR", "IndiceCombinado", "Quadrante"]
    el = d[d.Elegivel]
    pd.concat([g.nlargest(10, "IndiceCombinado") for _, g in el.groupby("GrupoAssistencial")])[cols] \
        .to_csv(out / "r1_top10_melhor_indice.csv", index=False)
    pd.concat([g.nsmallest(10, "IndiceCombinado") for _, g in el.groupby("GrupoAssistencial")])[cols] \
        .to_csv(out / "r1_top10_pior_indice.csv", index=False)
    el[el.Quadrante == "Crítico: IGR alto e TR baixa"].sort_values("IndiceCombinado")[cols] \
        .to_csv(out / "r1_criticas_igr_alto_tr_baixa.csv", index=False)

    med = el[el.GrupoAssistencial == "Médico-hospitalar"]
    res["_cor"] += [correl(med.IGR, med.TR_Geral, "IGR × TR (Geral)", "R1", "médico-hospitalar, elegíveis", log_y=False),
                    correl(med.BenefMedio, med.TR_Geral, "Beneficiários × TR (Geral)", "R1", "médico-hospitalar, elegíveis", log_y=False),
                    correl(med.BenefMedio, med.IGR, "Beneficiários × IGR", "R1", "médico-hospitalar, elegíveis"),
                    correl(med.Demandas, med.TR_Geral, "Demandas NIP × TR (Geral)", "R1", "médico-hospitalar, elegíveis", log_y=False)]
    odo = el[el.GrupoAssistencial == "Odontológico"]
    if len(odo) >= 10:
        res["_cor"].append(correl(odo.IGR, odo.TR_Geral, "IGR × TR (Geral)", "R1", "odontológico, elegíveis", log_y=False))
    seg = (el.groupby(["GrupoAssistencial", "Segmento"])
             .agg(Operadoras=("SkOperadora", "count"), Resolvidas=("Resolvidas", "sum"), Demandas=("Demandas", "sum"),
                  TR_Mediana=("TR_Geral", "median"), IGR_Mediana=("IGR", "median")).reset_index())
    seg["TR_Agregada"] = seg.Resolvidas / seg.Demandas * 100
    seg.to_csv(out / "r1_segmentos.csv", index=False)
    return d


def analise_temporal(t, out: Path, res: dict) -> None:
    fi = t["FatoIGR"].merge(t["DimTempo"], on="SkTempo")
    m = (fi.groupby(["SkTempo", "AnoMes", "Ano", "Mes", "SerieIGR", "SkCobertura"])
           .agg(Reclamacoes=("QtdReclamacoes", "sum"), Benef=("QtdBeneficiarios", "sum")).reset_index())
    m["IGR"] = m.Reclamacoes / m.Benef * 1e5
    m["Cobertura"] = m.SkCobertura.map(NOME_COB)
    m.to_csv(out / "serie_igr_mensal.csv", index=False)
    ft = t["FatoTR"][t["FatoTR"].SkNatureza != 3].merge(t["DimTempo"], on="SkTempo").merge(t["DimNatureza"], on="SkNatureza")
    tr = ft.groupby(["SkTempo", "AnoMes", "Ano", "Natureza"]).agg(Num=("Numerador", "sum"), Den=("Denominador", "sum")).reset_index()
    tot = tr.groupby(["SkTempo", "AnoMes", "Ano"])[["Num", "Den"]].sum().reset_index().assign(Natureza="Geral (A + N)")
    tr = pd.concat([tr, tot]); tr["TR"] = tr.Num / tr.Den * 100
    tr.to_csv(out / "serie_tr_mensal.csv", index=False)

    # Comparação anual em meses equivalentes (jan–out) para não comparar ano cheio com ano parcial
    viva = m[(m.SerieIGR == "VIGENTE") & (m.Mes <= 10)]
    anual = viva.groupby(["Cobertura", "Ano"])[["Reclamacoes", "Benef"]].sum().reset_index()
    anual = anual[anual.groupby(["Cobertura", "Ano"]).Ano.transform("size") > 0]
    meses_ano = viva.groupby(["Cobertura", "Ano"]).Mes.nunique().rename("Meses").reset_index()
    anual = anual.merge(meses_ano, on=["Cobertura", "Ano"])
    anual = anual[anual.Meses == 10]                  # só anos com jan–out completos
    anual["IGR_JanOut"] = anual.Reclamacoes / anual.Benef * 1e5
    anual["Var_pct"] = anual.groupby("Cobertura").IGR_JanOut.pct_change() * 100
    anual.to_csv(out / "igr_anual_jan_out.csv", index=False)

    tend = {}
    for cob in (COB_MED, COB_ODO):
        s = m[(m.SerieIGR == "VIGENTE") & (m.SkCobertura == cob)].sort_values("SkTempo")
        sp = stats.spearmanr(np.arange(len(s)), s.IGR)
        lr = stats.linregress(np.arange(len(s)), s.IGR)
        tend[NOME_COB[cob]] = {"meses": len(s), "spearman_tempo_rho": round(float(sp.statistic), 3), "p": float(sp.pvalue),
                               "inclinacao_por_mes": round(float(lr.slope), 3),
                               "inicio": round(float(s.IGR.iloc[:3].mean()), 2), "fim": round(float(s.IGR.iloc[-3:].mean()), 2)}
    g = tr[tr.Natureza == "Geral (A + N)"].sort_values("SkTempo")
    sp = stats.spearmanr(np.arange(len(g)), g.TR)
    tend["TR_geral_2015_2019"] = {"meses": len(g), "spearman_tempo_rho": round(float(sp.statistic), 3), "p": float(sp.pvalue),
                                  "inicio": round(float(g.TR.iloc[:3].mean()), 1), "fim": round(float(g.TR.iloc[-3:].mean()), 1)}
    res["temporal"] = {"tendencia": tend, "anual_jan_out": anual.round(2).to_dict("records")}

    # Segmentos médicos ano a ano (jan–out), série vigente
    fs = fi[(fi.SerieIGR == "VIGENTE") & (fi.Mes <= 10) & (fi.SkCobertura == COB_MED)] \
        .merge(t["Op"][["SkOperadora", "Segmento", "GrupoAssistencial"]], on="SkOperadora")
    fs = fs[fs.GrupoAssistencial == "Médico-hospitalar"]
    sa = fs.groupby(["Segmento", "Ano"]).agg(R=("QtdReclamacoes", "sum"), B=("QtdBeneficiarios", "sum"), M=("Mes", "nunique")).reset_index()
    sa = sa[sa.M == 10]; sa["IGR_JanOut"] = sa.R / sa.B * 1e5
    sa.pivot(index="Segmento", columns="Ano", values="IGR_JanOut").round(2).to_csv(out / "igr_segmento_ano_medico.csv")


# ----------------------------------------------------------------------------- figuras
AZUL, LARANJA, CINZA, TXT, TXT2 = "#257de0", "#f47230", "#9c9c9c", "#191919", "#666666"


def _eixo(ax):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.spines["left"].set_color("#cfcfcf"); ax.spines["bottom"].set_color("#cfcfcf")
    ax.tick_params(colors=TXT2, labelsize=8); ax.grid(axis="y", color="#ececec", linewidth=0.8); ax.set_axisbelow(True)


def figuras(out: Path, fig: Path, r2: pd.DataFrame, r1: pd.DataFrame) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.size": 9, "axes.titlesize": 10, "axes.titleweight": "bold", "text.color": TXT})
    fig.mkdir(parents=True, exist_ok=True)

    # 1. Série mensal do IGR — painéis separados por cobertura (escalas ~50× diferentes; sem eixo duplo)
    m = pd.read_csv(out / "serie_igr_mensal.csv")
    f, axs = plt.subplots(2, 1, figsize=(8, 5), sharex=True)
    for ax, cob in zip(axs, (NOME_COB[COB_MED], NOME_COB[COB_ODO])):
        s = m[m.Cobertura == cob].copy(); s["Data"] = pd.to_datetime(s.AnoMes + "-01")
        for serie, cor in (("CONGELADA", CINZA), ("VIGENTE", AZUL)):
            x = s[s.SerieIGR == serie]; ax.plot(x.Data, x.IGR, color=cor, lw=1.6)
        ax.axvspan(pd.Timestamp("2019-05-01"), pd.Timestamp("2021-04-30"), color="#f5f5f5", lw=0)
        ax.set_title(f"IGR mensal — {cob}", loc="left"); ax.set_ylabel("reclamações / 100 mil benef.", color=TXT2, fontsize=8); _eixo(ax)
    axs[0].text(pd.Timestamp("2019-06-01"), axs[0].get_ylim()[1] * .85, "sem publicação\n2019-05 a 2021-04", fontsize=7.5, color=TXT2)
    axs[0].text(pd.Timestamp("2015-02-01"), axs[0].get_ylim()[1] * .85, "série congelada", fontsize=7.5, color=CINZA)
    axs[0].text(pd.Timestamp("2021-06-01"), axs[0].get_ylim()[1] * .85, "série vigente", fontsize=7.5, color=AZUL)
    f.tight_layout(); f.savefig(fig / "01_serie_igr_mensal.png", dpi=160); plt.close(f)

    # 2. Funil de Poisson — assistência médica, R2
    x = r2[(r2.SkCobertura == COB_MED) & r2.Elegivel].sort_values("BenefSoma")
    f, ax = plt.subplots(figsize=(8, 4.6))
    dentro = x.Funil == "Dentro"
    ax.scatter(x[dentro].BenefMedio, x[dentro].IGR, s=14, color=CINZA, alpha=.6, lw=0, label="Dentro dos limites")
    ax.scatter(x[x.Funil == "Acima (pior)"].BenefMedio, x[x.Funil == "Acima (pior)"].IGR, s=18, color=LARANJA, lw=0, label="Acima (pior que o esperado)")
    ax.scatter(x[x.Funil == "Abaixo (melhor)"].BenefMedio, x[x.Funil == "Abaixo (melhor)"].IGR, s=18, color=AZUL, lw=0, label="Abaixo (melhor que o esperado)")
    ax.plot(x.BenefMedio, x.LimSupIGR, color=TXT2, lw=1, ls="--"); ax.plot(x.BenefMedio, x.LimInfIGR, color=TXT2, lw=1, ls="--")
    taxa = x.Reclamacoes.sum() / x.BenefSoma.sum() * 1e5
    ax.axhline(taxa, color=TXT2, lw=.8)
    ax.set_xscale("log"); ax.set_yscale("symlog", linthresh=10); ax.set_ylim(bottom=0)
    ax.text(x.BenefMedio.min(), taxa * 1.15, f"IGR do mercado: {taxa:.1f}", va="bottom", ha="left", fontsize=7.5, color=TXT2)
    ax.set_xlabel("beneficiários médios (escala log)", color=TXT2); ax.set_ylabel("IGR 12 meses", color=TXT2)
    ax.set_title("Funil de Poisson (ajustado para sobredispersão) — assistência médica, últimos 12 meses", loc="left")
    ax.legend(frameon=False, fontsize=7.5, loc="upper right"); _eixo(ax)
    f.tight_layout(); f.savefig(fig / "02_funil_igr_medico.png", dpi=160); plt.close(f)

    # 3. Dispersão IGR × TR — médico-hospitalar, R1, quadrantes por mediana
    e = r1[r1.Elegivel & (r1.GrupoAssistencial == "Médico-hospitalar")]
    mi, mt = e.IGR.median(), e.TR_Geral.median()
    f, ax = plt.subplots(figsize=(7.5, 4.6))
    crit = e.Quadrante == "Crítico: IGR alto e TR baixa"
    ax.scatter(e[~crit].IGR, e[~crit].TR_Geral, s=16, color=CINZA, alpha=.65, lw=0, label="Demais")
    ax.scatter(e[crit].IGR, e[crit].TR_Geral, s=20, color=LARANJA, lw=0, label="Crítico: IGR alto e TR baixa")
    ax.axvline(mi, color=TXT2, lw=.8, ls=":"); ax.axhline(mt, color=TXT2, lw=.8, ls=":")
    ax.set_xscale("log"); ax.set_xlabel("IGR 12 meses (escala log)", color=TXT2); ax.set_ylabel("TR geral (%)", color=TXT2)
    ax.set_title("IGR × TR — operadoras médico-hospitalares, mai/2018–abr/2019", loc="left")
    ax.legend(frameon=False, fontsize=7.5, loc="lower left"); _eixo(ax)
    f.tight_layout(); f.savefig(fig / "03_dispersao_igr_tr.png", dpi=160); plt.close(f)

    # 4. Distribuição do IGR por segmento — médico, R2
    s = r2[(r2.SkCobertura == COB_MED) & r2.Elegivel & (r2.GrupoAssistencial == "Médico-hospitalar")]
    ordem = s.groupby("Segmento").IGR.median().sort_values().index.tolist()
    f, ax = plt.subplots(figsize=(8.5, 3.8))
    bp = ax.boxplot([s[s.Segmento == g].IGR.values for g in ordem], orientation="horizontal", widths=.5, patch_artist=True,
                    medianprops={"color": AZUL, "lw": 2}, flierprops={"marker": "o", "ms": 3, "mfc": CINZA, "mec": "none"},
                    boxprops={"facecolor": "#cce3fd", "edgecolor": "#84b9f3"}, whiskerprops={"color": CINZA}, capprops={"color": CINZA})
    ax.set_yticks(range(1, len(ordem) + 1), [f"{g} (n={int((s.Segmento == g).sum())})" for g in ordem])
    ax.set_xscale("symlog", linthresh=10); ax.set_xlim(left=0); ax.set_xlabel("IGR 12 meses por operadora", color=TXT2)
    ax.set_title("Distribuição do IGR por segmento — assistência médica, últimos 12 meses", loc="left", x=-0.35); _eixo(ax); ax.grid(axis="x", color="#ececec")
    f.tight_layout(); f.savefig(fig / "04_igr_segmentos.png", dpi=160); plt.close(f)

    # 5. TR mensal por natureza (2015–2019)
    tr = pd.read_csv(out / "serie_tr_mensal.csv"); tr["Data"] = pd.to_datetime(tr.AnoMes + "-01")
    f, ax = plt.subplots(figsize=(8, 3.4))
    for nat, cor in (("Geral (A + N)", AZUL), ("Assistencial", LARANJA), ("Não Assistencial", "#00b894")):
        x = tr[tr.Natureza == nat]; ax.plot(x.Data, x.TR, color=cor, lw=1.6 if nat.startswith("Geral") else 1.1)
        ax.text(x.Data.iloc[-1], x.TR.iloc[-1], f" {nat}", fontsize=7.5, color=TXT, va="center")
    ax.set_ylabel("TR (%)", color=TXT2); ax.set_title("Taxa de Resolutividade mensal do mercado, 2015–2019", loc="left"); _eixo(ax)
    ax.set_xlim(right=pd.Timestamp("2020-09-01"))
    f.tight_layout(); f.savefig(fig / "05_tr_mensal.png", dpi=160); plt.close(f)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dw", default=str(ROOT / "data" / "processed" / "dw"))
    ap.add_argument("--out", default=str(ROOT / "data" / "processed" / "analises"))
    ap.add_argument("--fig", default=str(ROOT / "reports" / "figures"))
    a = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(name)s | %(message)s", stream=sys.stdout)
    out, fig = Path(a.out), Path(a.fig); out.mkdir(parents=True, exist_ok=True)
    t = carregar(Path(a.dw))
    res: dict = {"criterios": CRITERIOS}
    r2 = analise_r2(t, out, res)
    r1 = analise_r1(t, out, res)
    analise_temporal(t, out, res)
    cor = pd.DataFrame(res.pop("_cor")); cor.to_csv(out / "correlacoes.csv", index=False)
    res["correlacoes"] = cor.to_dict("records")
    (out / "resultados.json").write_text(json.dumps(res, indent=2, ensure_ascii=False, default=str), encoding="utf-8")
    figuras(out, fig, r2, r1)
    log.info("Análises gravadas em %s e figuras em %s", out, fig)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
