"""
Exporta o DW (SQL Server) para Parquet em data/processed/dw/ — insumo das análises estatísticas.

As análises leem exatamente o que o Power BI consome (dimensões e fatos do DW), sem recalcular regras do ODS.
Grava também data/processed/dw/_manifest.json com contagens e somas de controle, conferidas contra o banco.

Uso:  python -m src.analysis.export_dw
"""
from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

# Permite rodar tanto "python -m src.x.y" quanto o arquivo direto (ex.: botão Run do VS Code)
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "processed" / "dw"
TABLES = ["DimOperadora", "DimSegmento", "DimTempo", "DimCobertura", "DimNatureza", "DimPorte", "FatoIGR", "FatoTR"]
CHECKSUMS = {
    "FatoIGR": ["QtdReclamacoes", "QtdBeneficiarios"],
    "FatoTR": ["Numerador", "Denominador"],
}
log = logging.getLogger("export_dw")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(name)s | %(message)s", stream=sys.stdout)
    from src.common.db import get_engine

    OUT.mkdir(parents=True, exist_ok=True)
    engine = get_engine()
    manifest = {"exported_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"), "tables": {}}
    with engine.connect() as conn:
        id_exec = conn.exec_driver_sql(
            "SELECT MAX(IdExecucao) FROM CTL.Execucao WHERE Status = 'SUCESSO'").scalar_one()
        manifest["id_execucao_pipeline"] = id_exec
        for t in TABLES:
            df = pd.read_sql_query(f"SELECT * FROM DW.{t}", conn)
            info = {"rows": int(len(df))}
            for col in CHECKSUMS.get(t, []):
                db_sum = conn.exec_driver_sql(f"SELECT SUM(CAST({col} AS BIGINT)) FROM DW.{t}").scalar_one()
                file_sum = int(df[col].astype("int64").sum())
                if db_sum != file_sum:
                    raise RuntimeError(f"Soma divergente em {t}.{col}: banco={db_sum} arquivo={file_sum}")
                info[f"sum_{col}"] = file_sum
            df.to_parquet(OUT / f"{t}.parquet", index=False)
            manifest["tables"][t] = info
            log.info("%s: %s linhas", t, f"{len(df):,}")
    (OUT / "_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    log.info("Exportação concluída (pipeline IdExecucao=%s) em %s", id_exec, OUT.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
