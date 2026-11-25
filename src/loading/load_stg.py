"""
Fase 4 — Carga da camada STG (Bronze) no SQL Server.

Princípios:
  * Cópia fiel: todas as colunas como NVARCHAR, nomes originais do cabeçalho, campos vazios preservados como ''.
  * Nenhuma regra de negócio aqui (tipagem/padronização ficam nas procedures do ODS).
  * Rastreabilidade: IdExecucao, NrLinhaArquivo, ArquivoOrigem, Sha256 e DtCarga em cada linha;
    registro do arquivo em CTL.ArquivoCarregado e da etapa em CTL.LogEtapa.
  * Reexecução segura: carga transacional (TRUNCATE + INSERT + conferência de contagem);
    se o arquivo (sha256) já é o que está na STG, a etapa é marcada IGNORADO (use --force para recarregar).
  * Detecção de mudança de layout: se o cabeçalho do arquivo divergir da tabela STG, a carga é abortada.

Por que TRUNCATE em vez de acumular? IGR e TR são republicados mensalmente com TODO o histórico (e com
revisão retroativa, conforme as notas técnicas). Acumular cargas na STG duplicaria competências. O histórico
de versões fica preservado nos arquivos (data/raw/<fonte>/_history) e em CTL.ArquivoCarregado.

Uso:
    python -m src.loading.load_stg --emit-ddl      # gera sql/02_create_stg_tables.sql a partir dos arquivos reais
    python -m src.loading.load_stg --check         # testa conexão
    python -m src.loading.load_stg [--only igr tr] [--force] [--id-execucao N]
"""
from __future__ import annotations

import argparse
import json
import logging
import math
import sys
import time
from pathlib import Path

import pandas as pd

# Permite rodar tanto "python -m src.x.y" quanto o arquivo direto (ex.: botão Run do VS Code)
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from src.common.ans_csv import read_ans_csv

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data" / "raw"
MANIFEST = RAW / "manifest.json"
DDL_OUT = ROOT / "sql" / "02_create_stg_tables.sql"

# fonte -> (arquivo de dados relativo a data/raw, tabela STG)
TARGETS: dict[str, tuple[str, str]] = {
    "operadoras_ativas": ("operadoras_ativas/Relatorio_cadop.csv", "ANS_Organizacoes_Ativas"),
    "operadoras_canceladas": ("operadoras_canceladas/Relatorio_cadop_canceladas.csv", "ANS_Organizacoes_Canceladas"),
    "igr": ("igr/pda-023-igr.csv", "ANS_IGR"),
    "tr": ("tr/pda-048-taxa_de_resolutividade.csv", "ANS_TR"),
}
CONTROL_COLS = ["IdExecucao", "NrLinhaArquivo", "ArquivoOrigem", "Sha256", "DtCarga"]

log = logging.getLogger("load_stg")


# ----------------------------------------------------------------------------- utilitários puros (testáveis)
def column_size(max_len: int) -> int:
    """Tamanho NVARCHAR com folga: dobro do máximo observado, arredondado para cima em múltiplos de 50."""
    return int(min(4000, max(50, math.ceil(max(max_len, 1) * 2 / 50) * 50)))


def validate_header(columns: list[str]) -> None:
    bad = [c for c in columns if not c or "]" in c or c in CONTROL_COLS]
    if bad:
        raise ValueError(f"Cabeçalho com colunas inválidas/reservadas: {bad}")
    dup = {c for c in columns if columns.count(c) > 1}
    if dup:
        raise ValueError(f"Cabeçalho com colunas duplicadas: {sorted(dup)}")


def build_stg_ddl(table: str, df: pd.DataFrame, source_file: str) -> str:
    validate_header(list(df.columns))
    lens = {c: int(df[c].str.len().max() or 0) for c in df.columns}
    # vírgula ANTES do comentário (depois dele ela seria comentada e quebraria o DDL)
    cols = "\n".join(f"    [{c}] NVARCHAR({column_size(n)}) NULL,  -- máx. observado {n}" for c, n in lens.items())
    return f"""-- Origem: data/raw/{source_file} ({len(df):,} linhas no momento da geração)
IF OBJECT_ID(N'STG.{table}', N'U') IS NULL
CREATE TABLE STG.{table} (
    IdExecucao     INT           NOT NULL,
    NrLinhaArquivo INT           NOT NULL,   -- ordinal do registro no arquivo (cabeçalho = linha 1)
    ArquivoOrigem  NVARCHAR(260) NOT NULL,
    Sha256         CHAR(64)      NOT NULL,
    DtCarga        DATETIME2(0)  NOT NULL CONSTRAINT DF_STG_{table}_DtCarga DEFAULT SYSDATETIME(),
{cols}
    CONSTRAINT PK_STG_{table} PRIMARY KEY CLUSTERED (IdExecucao, NrLinhaArquivo)
);
GO
"""


def prepare_frame(df: pd.DataFrame, id_execucao: int, arquivo: str, sha: str) -> pd.DataFrame:
    out = df.copy()
    out.insert(0, "Sha256", sha)
    out.insert(0, "ArquivoOrigem", arquivo)
    out.insert(0, "NrLinhaArquivo", range(2, len(df) + 2))
    out.insert(0, "IdExecucao", id_execucao)
    return out


# ----------------------------------------------------------------------------- banco
def stg_columns(conn, table: str) -> list[tuple[str, int]]:
    rows = conn.exec_driver_sql(
        "SELECT c.name, c.max_length / 2 FROM sys.columns c WHERE c.object_id = OBJECT_ID(?) ORDER BY c.column_id",
        (f"STG.{table}",),
    ).all()
    return [(r[0], int(r[1])) for r in rows]


def start_execucao(conn, origem: str) -> int:
    return int(conn.exec_driver_sql(
        "SET NOCOUNT ON; DECLARE @id INT; EXEC CTL.usp_IniciarExecucao @Origem = ?, @IdExecucao = @id OUTPUT; SELECT @id;",
        (origem,),
    ).scalar_one())


def etapa(conn, id_exec: int, objeto: str, status: str, id_log: int | None = None, **kw) -> int:
    sql = ("SET NOCOUNT ON; DECLARE @l BIGINT = ?; EXEC CTL.usp_RegistrarEtapa @IdExecucao=?, @Etapa='CARGA_STG', "
           "@Objeto=?, @Status=?, @IdLog=@l OUTPUT, @LinhasLidas=?, @LinhasInseridas=?, @Mensagem=?; SELECT @l;")
    return int(conn.exec_driver_sql(sql, (id_log, id_exec, objeto, status, kw.get("lidas"), kw.get("inseridas"),
                                          kw.get("msg"))).scalar_one())


def load_one(engine, source: str, manifest: dict, id_exec: int, force: bool) -> dict:
    rel, table = TARGETS[source]
    path = RAW / rel
    meta = manifest["files"].get(f"data/raw/{rel}")
    if not path.exists() or meta is None:
        raise FileNotFoundError(f"{rel} não encontrado ou fora do manifesto — rode o download antes.")

    df, enc = read_ans_csv(path, keep_empty_as_text=True)
    validate_header(list(df.columns))
    t0 = time.perf_counter()

    with engine.begin() as conn:
        id_log = etapa(conn, id_exec, f"STG.{table}", "EM_ANDAMENTO")

    try:
        with engine.begin() as conn:
            db_cols = stg_columns(conn, table)
            if not db_cols:
                raise RuntimeError(f"STG.{table} não existe — execute sql/02_create_stg_tables.sql.")
            data_cols = [c for c, _ in db_cols if c not in CONTROL_COLS]
            if data_cols != list(df.columns):
                raise RuntimeError(f"Layout divergente em {rel}: arquivo={list(df.columns)} tabela={data_cols}")
            sizes = dict(db_cols)
            too_long = {c: int(df[c].str.len().max()) for c in df.columns if df[c].str.len().max() > sizes[c]}
            if too_long:
                raise RuntimeError(f"Valores maiores que a coluna STG em {rel}: {too_long}. Regere o DDL.")

            last = conn.exec_driver_sql(
                "SELECT TOP 1 Sha256, QtdLinhas FROM CTL.ArquivoCarregado WHERE TabelaDestino = ? ORDER BY IdArquivo DESC",
                (f"STG.{table}",),
            ).first()
            current = conn.exec_driver_sql(f"SELECT COUNT_BIG(*) FROM STG.{table}").scalar_one()
            if not force and last and last[0] == meta["sha256"] and current == last[1]:
                msg = "Arquivo idêntico ao já carregado (sha256); carga ignorada."
                etapa(conn, id_exec, f"STG.{table}", "IGNORADO", id_log, lidas=len(df), inseridas=0, msg=msg)
                log.info("%s: %s", table, msg)
                return {"table": table, "status": "IGNORADO", "rows": len(df)}

            conn.exec_driver_sql(f"TRUNCATE TABLE STG.{table}")
            frame = prepare_frame(df, id_exec, path.name, meta["sha256"])
            frame.to_sql(table, conn, schema="STG", if_exists="append", index=False, chunksize=5000)
            loaded = conn.exec_driver_sql(f"SELECT COUNT_BIG(*) FROM STG.{table} WHERE IdExecucao = ?", (id_exec,)).scalar_one()
            if loaded != len(df):
                raise RuntimeError(f"Contagem divergente em STG.{table}: arquivo={len(df)} banco={loaded}")
            conn.exec_driver_sql(
                """INSERT CTL.ArquivoCarregado (IdExecucao, Fonte, NomeArquivo, CaminhoRelativo, UrlOrigem, Sha256, Bytes,
                       Encoding, ServerLastModified, DtDownloadUtc, TabelaDestino, QtdLinhas)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                (id_exec, source, path.name, meta["path"], meta["url"], meta["sha256"], meta["bytes"], enc,
                 meta.get("server_last_modified"), meta.get("downloaded_at_utc"), f"STG.{table}", len(df)),
            )
            etapa(conn, id_exec, f"STG.{table}", "SUCESSO", id_log, lidas=len(df), inseridas=int(loaded),
                  msg=f"{time.perf_counter() - t0:.1f}s; encoding={enc}")
        log.info("%s: %s linhas carregadas (%.1fs)", table, f"{loaded:,}", time.perf_counter() - t0)
        return {"table": table, "status": "SUCESSO", "rows": int(loaded)}
    except Exception as e:
        with engine.begin() as conn:  # a transação da carga já foi revertida; registra a falha
            etapa(conn, id_exec, f"STG.{table}", "FALHA", id_log, lidas=len(df), inseridas=0, msg=str(e)[:4000])
        raise


def emit_ddl() -> None:
    parts = ["/* 02_create_stg_tables.sql — GERADO por src/loading/load_stg.py --emit-ddl a partir dos",
             "   cabeçalhos reais dos arquivos da ANS. Colunas com o nome original; tudo NVARCHAR (cópia fiel). */",
             "SET ANSI_NULLS ON;", "SET QUOTED_IDENTIFIER ON;", "GO",
             "USE ANS_BI;", "GO", ""]
    for source, (rel, table) in TARGETS.items():
        df, _ = read_ans_csv(RAW / rel, keep_empty_as_text=True)
        parts.append(build_stg_ddl(table, df, rel))
    DDL_OUT.write_text("\n".join(parts), encoding="utf-8")
    log.info("DDL gerado em %s", DDL_OUT.relative_to(ROOT))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--emit-ddl", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--only", nargs="*", choices=sorted(TARGETS))
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--id-execucao", type=int)
    args = ap.parse_args(argv)
    (ROOT / "logs").mkdir(exist_ok=True)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
                        handlers=[logging.StreamHandler(sys.stdout),
                                  logging.FileHandler(ROOT / "logs" / "loading.log", encoding="utf-8")])
    if args.emit_ddl:
        emit_ddl()
        return 0

    from src.common.db import get_engine

    engine = get_engine()
    if args.check:
        with engine.connect() as c:
            log.info("Conectado: %s | banco %s", c.exec_driver_sql("SELECT @@SERVERNAME").scalar_one(),
                     c.exec_driver_sql("SELECT DB_NAME()").scalar_one())
        return 0

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    own_exec = args.id_execucao is None
    with engine.begin() as conn:
        id_exec = args.id_execucao or start_execucao(conn, "python:load_stg")
    log.info("IdExecucao=%s", id_exec)
    results, status, msg = [], "SUCESSO", None
    try:
        for source in args.only or TARGETS:
            results.append(load_one(engine, source, manifest, id_exec, args.force))
    except Exception as e:
        status, msg = "FALHA", str(e)[:4000]
        log.exception("Falha na carga STG")
    finally:
        if own_exec:
            with engine.begin() as conn:
                conn.exec_driver_sql("EXEC CTL.usp_FinalizarExecucao @IdExecucao=?, @Status=?, @Mensagem=?",
                                     (id_exec, status, msg))
    log.info("Resumo: %s", results)
    return 0 if status == "SUCESSO" else 1


if __name__ == "__main__":
    raise SystemExit(main())
