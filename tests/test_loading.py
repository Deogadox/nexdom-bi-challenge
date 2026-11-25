"""Testes das partes puras da carga STG (sem banco)."""
from pathlib import Path

import pandas as pd
import pytest

from src.common.ans_csv import read_ans_csv
from src.loading.load_stg import build_stg_ddl, column_size, prepare_frame, validate_header

FIX = Path(__file__).parent / "fixtures" / "raw"


def test_column_size_bounds():
    assert column_size(0) == 50
    assert column_size(6) == 50
    assert column_size(60) == 150
    assert column_size(10_000) == 4000


def test_validate_header_rejects_reserved_and_duplicates():
    with pytest.raises(ValueError):
        validate_header(["A", "IdExecucao"])
    with pytest.raises(ValueError):
        validate_header(["A", "A"])
    validate_header(["REGISTRO_OPERADORA", "IGR"])


def test_stg_keeps_empty_strings_and_leading_zeros():
    df, _ = read_ans_csv(FIX / "igr" / "pda-023-igr.csv", keep_empty_as_text=True)
    assert df["REGISTRO_OPERADORA"].iloc[0] == "000515"
    assert not df.isna().any().any()  # vazios ficam como '' (fidelidade), nunca NaN


def test_ddl_uses_original_names_and_nvarchar():
    df, _ = read_ans_csv(FIX / "tr" / "pda-048-taxa_de_resolutividade.csv", keep_empty_as_text=True)
    ddl = build_stg_ddl("ANS_TR", df, "tr/x.csv")
    assert "[CD_REGISTRO_ANS] NVARCHAR(50)" in ddl
    assert "PRIMARY KEY CLUSTERED (IdExecucao, NrLinhaArquivo)" in ddl
    data_lines = [l for l in ddl.splitlines() if l.strip().startswith("[")]
    assert len(data_lines) == len(df.columns)
    assert all(" NVARCHAR(" in l for l in data_lines)  # colunas de dados só texto
    # toda linha de coluna termina a definição com vírgula fora do comentário
    assert all(l.split("--")[0].rstrip().endswith(",") for l in data_lines)


def test_prepare_frame_line_numbers_start_after_header():
    df = pd.DataFrame({"A": ["x", "y"]})
    out = prepare_frame(df, 7, "f.csv", "a" * 64)
    assert list(out.columns[:4]) == ["IdExecucao", "NrLinhaArquivo", "ArquivoOrigem", "Sha256"]
    assert out["NrLinhaArquivo"].tolist() == [2, 3]
