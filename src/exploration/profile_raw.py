"""
Fase 2 — Exploração/profiling das bases brutas (somente leitura de data/raw).

Gera:
  data/processed/profiling/profile.json  — métricas completas
  docs/profiling_raw.md                  — relatório legível

Verifica: colunas, tipos, nulos, cardinalidade, período, formato do registro ANS,
unicidade da granularidade esperada, consistência das fórmulas oficiais
(IGR = reclamações/beneficiários × 100.000; TR = numerador/denominador × 100)
e cobertura de chaves entre as bases.

Uso:
    python -m src.exploration.profile_raw [--raw data/raw]
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from src.common.ans_csv import normalize_registro, read_ans_csv, snake, to_num

ROOT = Path(__file__).resolve().parents[2]
log = logging.getLogger("profile_raw")

FILES = {
    "operadoras_ativas": "operadoras_ativas/Relatorio_cadop.csv",
    "operadoras_canceladas": "operadoras_canceladas/Relatorio_cadop_canceladas.csv",
    "igr": "igr/pda-023-igr.csv",
    "tr": "tr/pda-048-taxa_de_resolutividade.csv",
}

# Granularidade esperada (hipótese a validar) — após normalização de nomes
EXPECTED_GRAIN = {
    "operadoras_ativas": ["registro_ans"],
    "operadoras_canceladas": ["registro_ans"],
    "igr": ["registro_ans", "cobertura", "competencia"],
    "tr": ["registro_ans", "tp_natureza", "cd_competencia"],
}

REGISTRO_ALIASES = {"registro_ans", "registro_operadora", "cd_registro_ans", "reg_ans"}










def profile_df(df: pd.DataFrame) -> dict:
    cols = {}
    for c in df.columns:
        s = df[c]
        vc = s.value_counts(dropna=True)
        cols[c] = {
            "nulls": int(s.isna().sum()),
            "null_pct": round(float(s.isna().mean() * 100), 2),
            "distinct": int(s.nunique(dropna=True)),
            "top_values": {str(k): int(v) for k, v in vc.head(8).items()} if s.nunique() <= 60 else None,
            "max_len": int(s.dropna().str.len().max()) if s.notna().any() else 0,
        }
    return {"rows": int(len(df)), "columns": list(df.columns), "profile": cols}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(ROOT / "data" / "raw"))
    ap.add_argument("--out-json", default=str(ROOT / "data" / "processed" / "profiling" / "profile.json"))
    ap.add_argument("--out-md", default=str(ROOT / "docs" / "profiling_raw.md"))
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s", stream=sys.stdout)

    raw = Path(args.raw)
    out: dict = {}
    frames: dict[str, pd.DataFrame] = {}

    for key, rel in FILES.items():
        p = raw / rel
        if not p.exists():
            log.warning("Arquivo ausente: %s", p)
            out[key] = {"missing": True}
            continue
        df, enc = read_ans_csv(p)
        original_cols = list(df.columns)
        df.columns = [snake(c) for c in df.columns]
        reg_col = next((c for c in df.columns if c in REGISTRO_ALIASES), None)
        info = {"file": rel, "encoding": enc, "original_columns": original_cols, **profile_df(df)}

        if reg_col:
            raw_reg = df[reg_col].astype("string")
            info["registro_col"] = reg_col
            info["registro_len_dist"] = {str(k): int(v) for k, v in raw_reg.str.len().value_counts().items()}
            info["registro_non_digit"] = int(raw_reg.str.contains(r"\D", na=False).sum())
            df["registro_ans"] = normalize_registro(raw_reg)
            info["registro_distinct_norm"] = int(df["registro_ans"].nunique())

        # Granularidade
        grain = [c for c in EXPECTED_GRAIN[key] if c in df.columns]
        if len(grain) == len(EXPECTED_GRAIN[key]):
            dup = df.duplicated(grain, keep=False)
            info["grain"] = {"keys": grain, "duplicated_rows": int(dup.sum()), "unique": bool(not dup.any())}
            info["full_row_duplicates"] = int(df.duplicated(keep=False).sum())

        # Período
        comp_cols = [c for c in df.columns if "competencia" in c]
        for c in comp_cols:
            vals = df[c].dropna().sort_values()
            per = vals.value_counts().sort_index()
            info.setdefault("periods", {})[c] = {
                "min": vals.iloc[0] if len(vals) else None,
                "max": vals.iloc[-1] if len(vals) else None,
                "n_distinct": int(vals.nunique()),
                "rows_per_period_min": int(per.min()) if len(per) else None,
                "rows_per_period_max": int(per.max()) if len(per) else None,
            }
            if c in ("competencia", "cd_competencia"):
                expected = pd.period_range(vals.iloc[0], vals.iloc[-1], freq="M").astype(str)
                info["periods"][c]["missing_months"] = sorted(set(expected) - set(vals.unique()))

        # Consistência das fórmulas oficiais
        if key == "igr":
            igr, rec, ben = to_num(df["igr"]), to_num(df["qtd_reclamacoes"]), to_num(df["qtd_beneficiarios"])
            calc = np.where(ben > 0, rec / ben * 100_000, np.nan)
            diff = np.abs(calc - igr)
            info["formula_check"] = {
                "rows_with_ben_gt0": int((ben > 0).sum()),
                "rows_ben_zero_or_null": int(((ben == 0) | ben.isna()).sum()),
                "abs_diff_le_0_01_pct": round(float(np.nanmean(diff <= 0.01) * 100), 2),
                "abs_diff_p99": float(np.nanpercentile(diff, 99)) if np.isfinite(diff).any() else None,
                "igr_describe": igr.describe().round(3).to_dict(),
            }
        if key == "tr":
            vl, num, den = to_num(df["vl_tr"]), to_num(df["nr_numerador"]), to_num(df["nr_denominador"])
            calc = np.where(den > 0, num / den * 100, np.nan)
            diff = np.abs(calc - vl)
            info["formula_check"] = {
                "rows_den_zero_or_null": int(((den == 0) | den.isna()).sum()),
                "abs_diff_le_0_01_pct": round(float(np.nanmean(diff <= 0.01) * 100), 2),
                "num_gt_den": int((num > den).sum()),
                "denominador_describe": den.describe().round(2).to_dict(),
                "pct_rows_den_lt_10": round(float((den < 10).mean() * 100), 2),
            }
        frames[key] = df
        out[key] = info
        log.info("%s: %s linhas, %s colunas (%s)", key, len(df), len(original_cols), enc)

    # Cobertura de chaves entre bases
    if {"igr", "tr", "operadoras_ativas"} <= frames.keys():
        ativ = set(frames["operadoras_ativas"]["registro_ans"].dropna())
        canc = set(frames.get("operadoras_canceladas", pd.DataFrame({"registro_ans": []}))["registro_ans"].dropna())
        igr_r = set(frames["igr"]["registro_ans"].dropna())
        tr_r = set(frames["tr"]["registro_ans"].dropna())
        out["key_coverage"] = {
            "ativas": len(ativ),
            "canceladas": len(canc),
            "ativas_e_canceladas_overlap": len(ativ & canc),
            "igr_registros": len(igr_r),
            "tr_registros": len(tr_r),
            "igr_in_ativas": len(igr_r & ativ),
            "igr_in_canceladas_only": len((igr_r - ativ) & canc),
            "igr_sem_cadastro": sorted(igr_r - ativ - canc)[:50],
            "igr_sem_cadastro_n": len(igr_r - ativ - canc),
            "tr_in_ativas": len(tr_r & ativ),
            "tr_in_canceladas_only": len((tr_r - ativ) & canc),
            "tr_sem_cadastro_n": len(tr_r - ativ - canc),
            "tr_sem_cadastro": sorted(tr_r - ativ - canc)[:50],
            "igr_and_tr": len(igr_r & tr_r),
            "igr_only": len(igr_r - tr_r),
            "tr_only": len(tr_r - igr_r),
        }

    Path(args.out_json).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_json).write_text(json.dumps(out, indent=2, ensure_ascii=False, default=str), encoding="utf-8")
    Path(args.out_md).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_md).write_text(render_md(out), encoding="utf-8")
    log.info("Profiling gravado: %s | %s", args.out_json, args.out_md)
    return 0


def render_md(out: dict) -> str:
    lines = ["# Profiling das bases brutas (gerado automaticamente)", ""]
    for key, info in out.items():
        if key == "key_coverage":
            continue
        lines.append(f"## {key}")
        if info.get("missing"):
            lines += ["Arquivo ausente.", ""]
            continue
        lines.append(f"- Arquivo: `{info['file']}` | encoding: `{info['encoding']}` | linhas: **{info['rows']:,}**")
        if "grain" in info:
            g = info["grain"]
            lines.append(f"- Granularidade testada `{', '.join(g['keys'])}` → única: **{g['unique']}** (linhas duplicadas: {g['duplicated_rows']})")
        if "registro_len_dist" in info:
            lines.append(f"- Registro ANS: coluna `{info['registro_col']}`, tamanhos {info['registro_len_dist']}, não-dígitos: {info['registro_non_digit']}, distintos: {info['registro_distinct_norm']}")
        for c, p in info.get("periods", {}).items():
            miss = p.get("missing_months")
            lines.append(f"- Período `{c}`: {p['min']} → {p['max']} ({p['n_distinct']} competências; linhas/competência {p['rows_per_period_min']}–{p['rows_per_period_max']})" + (f"; meses faltantes: {miss}" if miss else ""))
        if "formula_check" in info:
            lines.append(f"- Checagem de fórmula: `{json.dumps(info['formula_check'], ensure_ascii=False, default=str)}`")
        lines += ["", "| coluna | nulos | % nulos | distintos | valores frequentes |", "|---|---|---|---|---|"]
        for c, p in info["profile"].items():
            tv = ", ".join(f"{k} ({v})" for k, v in list(p["top_values"].items())[:5]) if p["top_values"] else ""
            lines.append(f"| {c} | {p['nulls']} | {p['null_pct']} | {p['distinct']} | {tv} |")
        lines.append("")
    if "key_coverage" in out:
        lines += ["## Cobertura de chaves (registro ANS normalizado, 6 dígitos)", ""]
        lines += [f"- {k}: {v}" for k, v in out["key_coverage"].items()]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    raise SystemExit(main())
