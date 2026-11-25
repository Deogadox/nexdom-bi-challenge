"""Leitura dos CSVs da ANS como texto puro (sem inferência de tipo) e utilitários de inspeção."""
from __future__ import annotations

import re
import unicodedata
from pathlib import Path

import pandas as pd

ENCODINGS = ("utf-8-sig", "cp1252")


def read_ans_csv(path: Path, *, keep_empty_as_text: bool = False) -> tuple[pd.DataFrame, str]:
    """Lê CSV `;` da ANS com todas as colunas como str. Detecta encoding (UTF-8 ou CP1252).

    keep_empty_as_text=True mantém campos vazios como '' (fidelidade para a STG);
    False converte vazio em NaN (útil para profiling de nulos).
    """
    for enc in ENCODINGS:
        try:
            if keep_empty_as_text:
                df = pd.read_csv(path, sep=";", dtype=str, encoding=enc, na_filter=False)
            else:
                df = pd.read_csv(path, sep=";", dtype=str, encoding=enc, keep_default_na=False, na_values=[""])
            return df, enc
        except UnicodeDecodeError:
            continue
    raise ValueError(f"Encoding não suportado: {path}")


def snake(col: str) -> str:
    c = unicodedata.normalize("NFKD", col).encode("ascii", "ignore").decode()
    return re.sub(r"[^0-9a-zA-Z]+", "_", c).strip("_").lower()


def normalize_registro(s: pd.Series) -> pd.Series:
    digits = s.astype("string").str.replace(r"\D", "", regex=True)
    return digits.where(digits.str.len() > 0).str.zfill(6)


def to_num(s: pd.Series) -> pd.Series:
    t = s.astype("string").str.replace(".", "", regex=False).str.replace(",", ".", regex=False)
    return pd.to_numeric(t, errors="coerce")
