"""Testes da camada de exploração usando linhas reais copiadas dos arquivos da ANS (tests/fixtures/raw)."""
from pathlib import Path

import pandas as pd

from src.common.ans_csv import normalize_registro, read_ans_csv, snake, to_num

FIX = Path(__file__).parent / "fixtures" / "raw"


def test_normalize_registro_zfill_and_strip():
    s = pd.Series(["515", "000515", " 005711 ", "41.976-1", None, ""])
    out = normalize_registro(s).tolist()
    assert out[:4] == ["000515", "000515", "005711", "419761"]
    assert pd.isna(out[4]) and pd.isna(out[5])


def test_read_preserves_leading_zeros():
    df, enc = read_ans_csv(FIX / "igr" / "pda-023-igr.csv")
    assert df["REGISTRO_OPERADORA"].iloc[0] == "000515"
    assert enc in ("utf-8-sig", "cp1252")


def test_brazilian_decimal_parsing():
    assert to_num(pd.Series(["85,68", "1.234,5", "0,00"])).tolist() == [85.68, 1234.5, 0.0]


def test_snake_case_removes_accents():
    assert snake("Razão Social") == "razao_social"
    assert snake("CD_REGISTRO_ANS") == "cd_registro_ans"


def test_igr_formula_matches_official_definition():
    df, _ = read_ans_csv(FIX / "igr" / "pda-023-igr.csv")
    igr, rec, ben = to_num(df["IGR"]), to_num(df["QTD_RECLAMACOES"]), to_num(df["QTD_BENEFICIARIOS"])
    assert ((rec / ben * 100_000 - igr).abs() <= 0.01).all()


def test_tr_formula_matches_official_definition():
    df, _ = read_ans_csv(FIX / "tr" / "pda-048-taxa_de_resolutividade.csv")
    vl, num, den = to_num(df["VL_TR"]), to_num(df["NR_NUMERADOR"]), to_num(df["NR_DENOMINADOR"])
    assert ((num / den * 100 - vl).abs() <= 0.01).all()
